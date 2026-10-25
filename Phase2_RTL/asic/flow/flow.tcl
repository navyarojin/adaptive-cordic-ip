source [file join [file dirname [info script]] common.tcl]
set stages {
    {1 spec {Specification} Tcl}
    {2 rtl {RTL Design} Tcl}
    {3 sim {RTL Simulation} Xcelium}
    {4 lint {RTL Lint} JasperGold}
    {5 syn {Synthesis} Genus}
    {6 lec {LEC} Conformal}
    {7 pregls {Pre-Layout GLS} Xcelium}
    {8 floor {Floorplanning} Innovus}
    {9 power {Power Planning} Innovus}
    {10 place {Placement} Innovus}
    {11 cts {Clock Tree Synthesis} Innovus}
    {12 route {Routing} Innovus}
    {13 pex {PEX} Quantus}
    {14 sta {Post-Layout STA} Tempus}
    {15 postgls {Post-Layout GLS} Xcelium}
    {16a drc {DRC} {Pegasus/PVS}}
    {16b arc {Antenna Rule Check} {Pegasus/PVS}}
    {17 lvs {LVS} {Pegasus/PVS}}
    {18 eco {ECO} Innovus}
    {19 final_lec {Final LEC} Conformal}
}
proc run_logged {command log {directory {}}} {
    if {[auto_execok [lindex $command 0]] eq ""} {error "Tool not on PATH: [lindex $command 0]"}
    file mkdir [file dirname $log]
    puts "RUN: $command"
    puts "LOG: $log"
    set previous [pwd]
    if {$directory eq ""} {set directory [file dirname $log]}
    file mkdir $directory
    cd $directory
    set status [catch {exec {*}$command > $log 2>@1} message]
    cd $previous
    if {$status} {error "$message; inspect $log"}
}
proc launch {stage} {
    global cfg stages asic_dir rtl_dir flow_dir out rev_dir
    set valid {}
    foreach row $stages {lappend valid [lindex $row 1]}
    if {$stage ni $valid} {error "Unknown stage: $stage; use list"}
    if {$stage eq "spec"} {
        set fd [open [file join $asic_dir plan.json] r]; puts [read $fd]; close $fd
        return
    }
    if {$stage eq "rtl"} {puts [join [source_list] \n]; return}
    if {$stage eq "sim"} {run_cmd [list bash [file join $asic_dir uvm.sh] 1]; return}
    preflight $stage
    file mkdir $out
    set ::env(ASIC_STAGE) $stage
    set ::env(ASIC_OUT) $out
    set ::env(ASIC_REV) $cfg(revision)
    set driver [file join $flow_dir tool.tcl]
    set log [file join $out logs ${stage}_$cfg(revision).log]
    switch -- $stage {
        syn {run_logged [concat $cfg(genus) [list -no_gui -f $driver]] $log}
        floor - power - place - cts - route - eco - pex {
            if {$stage eq "pex" && [auto_execok qrc] eq ""} {error "Quantus qrc is not on PATH"}
            run_logged [concat $cfg(innovus) [list -no_gui -files $driver]] $log
        }
        sta {run_logged [concat $cfg(tempus) [list -no_gui -files $driver]] $log}
        lint {
            run_logged [concat $cfg(jasper) [list -batch -tcl $driver]] $log
            run_cmd [concat $cfg(lint_check) [list [file join $out lint]]]
        }
        lec {
            foreach name {rtl_map map_syn} {
                set dofile [file join $out syn ${name}.do]
                files_exist [list $dofile]
                set log [file join $out logs ${name}.log]
                run_logged [concat $cfg(conformal) [list -nogui -dofile $dofile]] $log [file join $out syn]
                run_cmd [concat $cfg(lec_check) [list $log]]
            }
        }
        final_lec {
            run_logged [concat $cfg(conformal) [list -nogui -tclmode -dofile [file join $flow_dir lec.tcl]]] $log
            run_cmd [concat $cfg(lec_check) [list $log]]
        }
        pregls - postgls {source [file join $flow_dir gls.tcl]}
        drc - arc - lvs {source [file join $flow_dir pv.tcl]}
    }
    switch -- $stage {
        syn {files_exist [list [file join $out syn design.v] [file join $out syn design.sdc] [file join $out syn design.sdf] [file join $out syn rtl_map.do] [file join $out syn map_syn.do]]}
        floor - power - place - cts {files_exist [list [file join $out pnr ${stage}.enc]]}
        route - eco {files_exist [list [file join $out $stage design.enc] [file join $out $stage design.v] [file join $out $stage design.gds] [file join $out $stage power.v]]}
        pex {files_exist [list [file join $rev_dir pex max.spef] [file join $rev_dir pex min.spef]]}
        sta {files_exist [list [file join $rev_dir sta design.sdf] [file join $rev_dir sta setup.rpt] [file join $rev_dir sta hold.rpt]]}
    }
    puts "Completed $stage execution. Review reports; no automatic tape-out/sign-off claim."
}
if {[catch {
    set stage [lindex $argv 0]
    switch -- $stage {
        {} - list - help - --help {
            puts "Usage: bash asic/run.sh <stage>; ASIC_CONFIG=/path/site.tcl for PDK settings"
            foreach row $stages {puts [format "%4s %-10s %-24s %s" {*}$row]}
        }
        check {
            source_list
            foreach file [glob -directory $flow_dir *.tcl *.sdc] {
                set fd [open $file r]; set text [read $fd]; close $fd
                if {![info complete $text]} {error "Incomplete Tcl syntax: $file"}
            }
            if {[llength $argv] > 1} {
                set selected [lindex $argv 1]
                set valid {}
                foreach row $stages {lappend valid [lindex $row 1]}
                if {$selected ni $valid} {error "Unknown stage: $selected"}
                preflight $selected
            }
            puts "PASS: ASIC Tcl structure and RTL source inventory. PDK/tool execution is separate."
        }
        default {launch $stage}
    }
} message]} {
    puts stderr "ASIC flow stopped: $message"
    exit 2
}
