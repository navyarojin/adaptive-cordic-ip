set board [file normalize [file join [file dirname [info script]] ..]]
set work [file join $board work_power]
set report_dir [file join $board reports power_comparison_20261028]
file mkdir $report_dir
set_param general.maxThreads 2
foreach variant {gated ungated} {
  set target zero_aware_systolic_npu_param
  if {$variant eq "ungated"} {set target ungated_systolic_npu_param}
  set variant_dir [file join $report_dir $variant]
  file mkdir $variant_dir
  create_project -in_memory -part xc7z020clg400-1
  read_verilog -sv [file join $work ${variant}.sv]
  synth_design -top $target -part xc7z020clg400-1 -mode out_of_context
  create_clock -name clk -period 40 [get_ports clk]
  set inputs [get_ports -filter {DIRECTION == IN && NAME != clk}]
  set_input_delay 0 -clock clk $inputs
  set_output_delay 0 -clock clk [get_ports -filter {DIRECTION == OUT}]
  opt_design
  place_design
  route_design
  report_timing_summary -delay_type min_max -file [file join $variant_dir timing.rpt]
  report_utilization -hierarchical -file [file join $variant_dir utilization.rpt]
  read_saif -strip_path tb_zero_aware/$variant -out_file [file join $variant_dir activity_annotation.txt] [file join $work activity.saif]
  report_power -file [file join $variant_dir power.rpt]
  report_power -format xml -file [file join $variant_dir power.xml]
  write_checkpoint -force [file join $variant_dir routed.dcp]
  close_project
}
puts "PASS matched routed MAC block power estimates: $report_dir"
