proc src_name {name} {
  set names [dict create fx_signed_divider_stream div_stream cordic_activation_stream act_stream]
  if {[dict exists $names $name]} {return [dict get $names $name]}
  return $name
}
set board [file normalize [file join [file dirname [info script]] ..]]
set root [file normalize [file join $board ..]]
set out [file join $board reports stream_compact_verify]
file mkdir $out
set_param general.maxThreads 2
create_project -in_memory -part xc7z020clg400-1
foreach name {fx_signed_divider_stream cordic_activation_stream} {
  read_verilog -sv [list [file join $root rtl [src_name $name].sv]]
}
synth_design -top cordic_activation_stream -part xc7z020clg400-1 -mode out_of_context
create_clock -name clk -period 40 [get_ports clk]
report_utilization -file [file join $out synthesis_area.rpt]
opt_design
place_design
route_design
report_timing_summary -file [file join $out timing.rpt]
report_utilization -file [file join $out area.rpt]
report_power -file [file join $out power.rpt]
report_drc -file [file join $out drc.rpt]
write_checkpoint -force [file join $out routed.dcp]
close_project
