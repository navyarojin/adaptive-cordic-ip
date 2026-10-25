source [file join [file dirname [info script]] common.tcl]
set stage $::env(ASIC_STAGE)
preflight $stage
if {$stage eq "pregls"} {
    set netlist [file join $out syn design.v]
    set sdf [file join $out syn design.sdf]
    set corners {MAXIMUM}
} else {
    set netlist [file join $rev_dir design.v]
    set sdf [file join $rev_dir sta design.sdf]
    set corners {MINIMUM MAXIMUM}
}
set verification [list [file join $rtl_dir uvm_tb tb ref.sv] [file join $asic_dir uvm stream_if.sv] [file join $asic_dir uvm uvm_pkg.sv] [file join $flow_dir gls.sv]]
files_exist [concat [list $netlist $sdf] $verification $cfg(sim_models)]
foreach corner $corners {
    set directory [file join $out gls $cfg(revision) $stage $corner]
    file mkdir $directory
    cd $directory
    foreach name {model.mem inputs.mem} {file copy -force [file join $rtl_dir evaluation data $name] $name}
    set command [concat $cfg(xrun) [list -64bit -uvm -sv -access +rwc -timescale 1ns/1ps -top gls_top -l run.log] $cfg(sim_models) [list $netlist] $verification [list +CLK_NS=$cfg(period) +SAMPLE_NS=[expr {$cfg(period)/4.0}] +SDF=$sdf +CORNER=$corner]]
    run_cmd $command
    files_exist [list run.log sdf.log]
    set fd [open run.log r]; set log [read $fd]; close $fd
    set fd [open sdf.log r]; append log \n [read $fd]; close $fd
    if {![string match {*PASS stream_model_test*} $log] || [regexp -nocase {\*[EF],|\*W,SDF|UVM_(ERROR|FATAL)\s+@|timing violation} $log]} {error "GLS failed or has SDF/timing diagnostics: $directory"}
    puts "GLS completed for $corner. Inspect SDF annotation counts and all timing checks in $directory."
}
