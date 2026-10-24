set board [file normalize [file join [file dirname [info script]] ..]]
set out [file join $board reports build_streaming_parallel]
set project_file [file join $out project npu_jupyter.xpr]
if {[file exists $project_file]} {
  open_project $project_file
} else {
  set streaming 1
  if {![info exists stream_lanes]} {set stream_lanes 4}
  source [file join $board scripts create.tcl]
}
open_bd_design [get_files npu_system.bd]
set_property CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} [get_bd_cells ps7]
validate_bd_design
if {[get_property CONFIG.PCW_S_AXI_HP0_DATA_WIDTH [get_bd_cells ps7]] ne "64"} {
  error "PYNQ boot configuration requires a 64-bit HP0 port"
}
save_bd_design
generate_target all [get_files npu_system.bd]
add_files -fileset sim_1 -norecurse [list [file join $board sim tb_stream_dma.sv]]
set_property top tb_stream_dma [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation
run 2ms
set passed [get_value /tb_stream_dma/test_passed]
close_sim
if {$passed ne "1"} {error "64-bit HP0 vendor DMA regression failed"}
set_property top tb_streaming [get_filesets sim_1]
set_property xsim.simulate.runtime 300ms [get_filesets sim_1]
reset_run npu_system_npu_host_0_synth_1
reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
launch_runs impl_1 -to_step route_design -jobs 2
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
open_run impl_1
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out time.rpt]
report_drc -file [file join $out drc.rpt]
report_cdc -file [file join $out cdc.rpt]
report_utilization -hierarchical -file [file join $out utilization_hierarchical.rpt]
report_utilization -file [file join $out area.rpt]
report_power -file [file join $out power.rpt]
foreach kind {max min} {
  if {[llength [get_timing_paths -quiet -delay_type $kind -slack_lesser_than 0 -max_paths 1]]} {error "$kind timing failed"}
}
set bundle [file join $board jupyter_streaming]
file mkdir $bundle
write_bitstream -force [file join $bundle board.bit]
set hwh [file join $out project npu_jupyter.gen sources_1 bd npu_system hw_handoff npu_system.hwh]
if {![file exists $hwh]} {error "HWH export missing"}
file copy -force $hwh [file join $bundle board.hwh]
foreach name {client.py stream.py stream.ipynb run.py bench.py} {
  if {[file normalize $bundle] ne [file normalize [file join $board jupyter_streaming]]} {
      file copy -force [file join $board jupyter_streaming $name] [file join $bundle $name]
    }
}
file copy -force [file join $root evaluation data model.json] [file join $bundle model.json]
puts "Streaming overlay exported to $bundle"
