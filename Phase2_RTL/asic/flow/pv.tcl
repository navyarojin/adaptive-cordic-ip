source [file join [file dirname [info script]] common.tcl]
set stage $::env(ASIC_STAGE)
preflight $stage
files_exist [list [file join $rev_dir design.gds] [file join $rev_dir power.v]]
set directory [file join $rev_dir $stage]
file mkdir $directory
set ::env(ASIC_TOP) $cfg(top)
set ::env(ASIC_GDS) [file join $rev_dir design.gds]
set ::env(ASIC_NETLIST) [file join $rev_dir power.v]
set ::env(ASIC_REPORT) [file join $directory report.txt]
cd $directory
run_cmd $cfg(${stage}_cmd)
files_exist [list $::env(ASIC_REPORT)]
run_cmd [concat $cfg(${stage}_check) [list $::env(ASIC_REPORT)]]
puts "$stage report accepted by the configured PDK checker. Preserve the runset, logs, violations and review evidence."
