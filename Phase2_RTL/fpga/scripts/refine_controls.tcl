set board [file normalize [file join [file dirname [info script]] ..]]
set out [file join $board work_closure]
set report_dir [file join $board reports engineering_closure_20261028]
set_param general.maxThreads 2
open_checkpoint [file join $board work_closure project npu_jupyter.runs impl_1 npu_system_wrapper_opt.dcp]
source [file join $board scripts remap_controls.tcl]
opt_design
report_control_sets -verbose -file [file join $report_dir control_sets_remapped_before_place.rpt]
place_design
phys_opt_design
route_design
source [file join $board scripts export_engineering.tcl]
close_project
