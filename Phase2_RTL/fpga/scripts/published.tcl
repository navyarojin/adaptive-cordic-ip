proc src_name {name} {
  set names [dict create fx_signed_divider_stream div_stream cordic_activation_stream act_stream]
  if {[dict exists $names $name]} {return [dict get $names $name]}
  return $name
}
set board [file normalize [file join [file dirname [info script]] ..]]
set root [file normalize [file join $board ..]]
set source_dir [file join $root evaluation comparison published_baseline]
set out [file join $board reports published_verify]
file mkdir $out
set_param general.maxThreads 2
set benchmarks {published_sigmoid_benchmark cordic_sigmoid_benchmark}
if {[llength $argv]} {set benchmarks $argv}
foreach top $benchmarks {
  if {$top ni {published_sigmoid_benchmark cordic_sigmoid_benchmark}} {error "Unknown benchmark $top"}
  create_project -in_memory -part xc7z020clg400-1
  set_property include_dirs [list $source_dir] [current_fileset]
  foreach name {fx_signed_divider_stream cordic_activation_stream} {
    read_verilog -sv [list [file join $root rtl [src_name $name].sv]]
  }
  read_verilog -sv [list [file join $source_dir wrap.sv]]
  synth_design -top $top -part xc7z020clg400-1 -mode out_of_context
  create_clock -name clk -period 40 [get_ports clk]
  opt_design
  place_design
  route_design
  set prefix [expr {$top eq "published_sigmoid_benchmark" ? "published" : "cordic"}]
  report_timing_summary -file [file join $out ${prefix}_time.rpt]
  report_utilization -file [file join $out ${prefix}_area.rpt]
  report_power -file [file join $out ${prefix}_power.rpt]
  report_drc -file [file join $out ${prefix}_drc.rpt]
  write_checkpoint -force [file join $out ${top}_routed.dcp]
  close_project
}
