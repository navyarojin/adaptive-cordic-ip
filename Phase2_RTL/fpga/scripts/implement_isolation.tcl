set board [file normalize [file join [file dirname [info script]] ..]]
set work [file join $board work_isolation]
set report_dir [file join $board reports isolation_hold_20261028]
file mkdir $report_dir
file mkdir [file join $work netlists]
set_param general.maxThreads 2
foreach {variant filename target} {
  legacy legacy.sv zero_aware_systolic_npu_param
  plain plain.sv ungated_systolic_npu_param
  retained retained.sv retained_systolic_npu_param
  isolated zero_hold.sv zero_hold_systolic_npu_param
  dual zero_dual_hold.sv zero_dual_hold_systolic_npu_param
} {
  set variant_dir [file join $report_dir $variant]
  file mkdir $variant_dir
  create_project -in_memory -part xc7z020clg400-1
  read_verilog -sv [file join $work $filename]
  synth_design -top $target -part xc7z020clg400-1 -mode out_of_context -flatten_hierarchy full -max_dsp 0
  create_clock -name clk -period 40 [get_ports clk]
  set_input_delay 0 -clock clk [get_ports -filter {DIRECTION == IN && NAME != clk}]
  set_output_delay 0 -clock clk [get_ports -filter {DIRECTION == OUT}]
  opt_design
  place_design
  route_design
  report_timing_summary -delay_type min_max -file [file join $variant_dir timing.rpt]
  report_utilization -file [file join $variant_dir utilization.rpt]
  write_checkpoint -force [file join $variant_dir routed.dcp]
  set sdf_file [file join $work netlists ${variant}.sdf]
  write_sdf -force $sdf_file
  write_verilog -force -mode timesim -sdf_anno true -sdf_file $sdf_file [file join $work netlists ${variant}.v]
  close_project
}
puts "PASS isolation implementations and SDF timing netlists"
