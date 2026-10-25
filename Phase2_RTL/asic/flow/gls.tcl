source [file join [file dirname [info script]] common.tcl]
set stage $::env(ASIC_STAGE)
preflight $stage
if {$stage eq "sim"} {
    set design_sources [source_list]
    set sdf {}
    set corners {RTL}
} elseif {$stage eq "pregls"} {
    set netlist [file join $out syn design.v]
    set sdf [file join $out syn design.sdf]
    set corners {MAXIMUM}
} else {
    set netlist [file join $rev_dir design.v]
    set sdf [file join $rev_dir sta design.sdf]
    set corners {MINIMUM MAXIMUM}
}
if {$stage ne "sim"} {set design_sources [list $netlist]}
set models $cfg(sim_models)
set defines {}
if {$cfg(top) eq "chip"} {
    foreach model $cfg(pad_models) {if {$model ni $models} {lappend models $model}}
    lappend defines +define+ASIC_CHIP_TOP
}
if {$stage eq "sim"} {lappend defines +define+ASIC_RTL_SIM}
set verification [list [file join $rtl_dir uvm_tb tb ref.sv] [file join $asic_dir uvm stream_if.sv] [file join $asic_dir uvm uvm_pkg.sv] [file join $flow_dir gls.sv]]
files_exist [concat $design_sources $verification $models]
if {$sdf ne ""} {files_exist [list $sdf]}
foreach corner $corners {
    set directory [file join $out gls $cfg(revision) $stage $corner]
    file mkdir $directory
    cd $directory
    foreach name {model.mem inputs.mem} {file copy -force [file join $rtl_dir evaluation data $name] $name}
    set command [concat $cfg(xrun) [list -64bit -uvm -sv -access +rwc -timescale 1ns/1ps -top gls_top -l run.log] $models $design_sources $verification $defines [list +CLK_NS=$cfg(period) +SAMPLE_NS=[expr {$cfg(period)/4.0}] +SDF=$sdf +CORNER=$corner]]
    run_cmd $command
    files_exist [list run.log]
    if {$stage ne "sim"} {files_exist [list sdf.log]}
    set fd [open run.log r]; set log [read $fd]; close $fd
    if {$stage ne "sim"} {set fd [open sdf.log r]; append log \n [read $fd]; close $fd}
    if {![string match {*PASS stream_model_test*} $log] || [regexp -nocase {\*[EF],|\*W,SDF|UVM_(ERROR|FATAL)\s+@|timing violation} $log]} {error "GLS failed or has SDF/timing diagnostics: $directory"}
    puts "Simulation completed for $corner: $directory. Review timing/SDF diagnostics for gate-level runs."
}
