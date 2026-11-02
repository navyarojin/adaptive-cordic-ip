set board [file normalize [file join [file dirname [info script]] ..]]
if {![info exists out]} {set out [file join $board reports build_streaming_parallel]}
set project_file [file join $out project npu_jupyter.xpr]
if {[file exists $project_file]} {
  open_project $project_file
} else {
  set streaming 1
  if {![info exists stream_lanes]} {set stream_lanes 4}
  source [file join $board scripts create.tcl]
}
open_bd_design [get_files npu_system.bd]
if {[get_property CONFIG.PCW_S_AXI_HP0_DATA_WIDTH [get_bd_cells ps7]] ne "64"} {
  error "PYNQ boot configuration requires a 64-bit HP0 port"
}
add_files -fileset sim_1 -norecurse [list [file join $board sim tb_stream_dma.sv]]
set_property top tb_stream_dma [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation
run 2ms
set passed [get_value /tb_stream_dma/test_passed]
close_sim
if {$passed ne "1"} {error "Vendor AXI DMA regression failed"}
