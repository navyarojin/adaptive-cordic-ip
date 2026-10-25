set flow_dir [file normalize [file dirname [info script]]]
set asic_dir [file dirname $flow_dir]
set rtl_dir [file dirname $asic_dir]
source [file join $flow_dir config.tcl]
if {[info exists ::env(ASIC_OUT)]} {
    set out [file normalize $::env(ASIC_OUT)]
} else {
    set out [file join $asic_dir work]
}
if {[info exists ::env(ASIC_CONFIG)]} {
    set site_config [file normalize $::env(ASIC_CONFIG)]
    if {![file isfile $site_config]} {error "Missing ASIC_CONFIG: $site_config"}
    source $site_config
    set ::env(ASIC_CONFIG) $site_config
}
if {[info exists ::env(ASIC_REV)]} {set cfg(revision) $::env(ASIC_REV)}
if {$cfg(top) ne "stream_mmio"} {error "The supplied verification harness targets stream_mmio only"}
if {$cfg(revision) ni {route eco}} {error "ASIC_REV must be route or eco"}
foreach key {lib_max lib_min lef sim_models lec_models gds_cells} {
    set paths {}
    foreach path $cfg($key) {lappend paths [file normalize $path]}
    set cfg($key) $paths
}
foreach key {qrc_max qrc_min gds_map floor_hook finish_hook sta_hook eco_hook lint_hook} {
    if {$cfg($key) ne ""} {set cfg($key) [file normalize $cfg($key)]}
}
if {$cfg(period)<=0 || $cfg(input_delay)<0 || $cfg(output_delay)<0 || $cfg(uncertainty)<0} {error "Invalid timing budget"}
set rev_dir [file join $out $cfg(revision)]
proc need {args} {
    global cfg
    foreach key $args {
        if {![info exists cfg($key)] || $cfg($key) eq ""} {error "Set cfg($key) in ASIC_CONFIG or flow/config.tcl"}
    }
}
proc files_exist {paths} {
    foreach path $paths {
        if {![file isfile $path] || [file size $path] == 0} {error "Missing or empty file: $path"}
    }
}
proc source_list {} {
    global asic_dir rtl_dir
    set fd [open [file join $asic_dir verification.f] r]
    set result {}
    foreach line [split [read $fd] \n] {
        set line [string trim $line]
        if {$line ne ""} {lappend result [file normalize [file join $rtl_dir $line]]}
    }
    close $fd
    files_exist $result
    return $result
}
proc hook {key} {
    global cfg
    need $key
    files_exist [list $cfg($key)]
    uplevel #0 [list source $cfg($key)]
}
proc run_cmd {command} {
    if {[llength $command] == 0} {error "Empty tool command"}
    if {[auto_execok [lindex $command 0]] eq ""} {error "Tool not on PATH: [lindex $command 0]"}
    puts "RUN: $command"
    exec {*}$command >@ stdout 2>@ stderr
}
proc preflight {stage} {
    global cfg out rev_dir
    source_list
    switch -- $stage {
        syn {need lib_max; files_exist $cfg(lib_max)}
        lint {need lint_hook lint_check; files_exist [list $cfg(lint_hook)]}
        floor - power - place - cts - route - eco - pex {
            need lib_max lib_min lef qrc_max qrc_min temp_max temp_min site
            files_exist [concat $cfg(lib_max) $cfg(lib_min) $cfg(lef) [list $cfg(qrc_max) $cfg(qrc_min)]]
            if {$stage eq "floor"} {need floor_hook; files_exist [list $cfg(floor_hook)]}
            if {$stage eq "power"} {need ring_h ring_v ring_width ring_spacing ring_offset stripe_layer stripe_width stripe_pitch}
            if {$stage eq "route" || $stage eq "eco"} {
                need finish_hook gds_map gds_cells
                files_exist [concat [list $cfg(finish_hook) $cfg(gds_map)] $cfg(gds_cells)]
            }
            if {$stage eq "eco"} {need eco_hook; files_exist [list $cfg(eco_hook)]}
            if {$stage eq "cts"} {need cts_buffers cts_inverters cts_transition cts_skew}
            if {$stage eq "route"} {need route_bottom route_top}
        }
        sta {need lib_max lib_min qrc_max qrc_min temp_max temp_min sta_hook; files_exist [concat $cfg(lib_max) $cfg(lib_min) [list $cfg(qrc_max) $cfg(qrc_min) $cfg(sta_hook)]]}
        pregls - postgls {need sim_models; files_exist $cfg(sim_models)}
        final_lec {need lib_max lec_check; files_exist [concat $cfg(lib_max) $cfg(lec_models)]}
        lec {need lec_check}
        drc - arc - lvs {need ${stage}_cmd ${stage}_check}
    }
}
