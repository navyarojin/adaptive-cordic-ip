set board [file normalize [file join [file dirname [info script]] ..]]
set streaming 1
set stream_lanes 4
if {![info exists out]} {set out [file join $board work_closure]}
if {![info exists report_dir]} {set report_dir [file join $board reports engineering_closure_20261028]}
set ::env(NPU_REPORT_DIR) $report_dir
file mkdir $report_dir
set_param general.maxThreads 2
source [file join $board scripts create.tcl]
foreach run [get_runs -filter {IS_SYNTHESIS == 1}] {
  set_property STEPS.SYNTH_DESIGN.ARGS.CONTROL_SET_OPT_THRESHOLD 16 $run
}
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
set_property STEPS.OPT_DESIGN.TCL.PRE [file join $board scripts remap_controls.tcl] [get_runs impl_1]
launch_runs impl_1 -to_step route_design -jobs 2
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
open_run impl_1
source [file join $board scripts export_engineering.tcl]
close_project
