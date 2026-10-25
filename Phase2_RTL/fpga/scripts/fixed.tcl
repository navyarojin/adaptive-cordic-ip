proc src_name {name} {
  set names [dict create fx_signed_divider_stream div_stream cordic_activation_stream act_stream]
  if {[dict exists $names $name]} {return [dict get $names $name]}
  return $name
}
set board [file normalize [file join [file dirname [info script]] ..]]
set root [file normalize [file join $board ..]]
if {$argc!=1} {error "Supply report output directory"}
set out [file normalize [lindex $argv 0]]
file mkdir $out
set_param general.maxThreads 2
create_project -in_memory -part xc7z020clg400-1
foreach name {fx_signed_divider_stream cordic_activation_stream} {
  read_verilog -sv [list [file join $root rtl [src_name $name].sv]]
}
read_verilog -sv [list [file join $root evaluation comparison fixed.sv]]
synth_design -top fixed_activation_baseline -part xc7z020clg400-1 -mode out_of_context
create_clock -name clk -period 40 [get_ports clk]
report_utilization -file [file join $out fixed_area.rpt]
report_timing_summary -file [file join $out fixed_time.rpt]
close_project
