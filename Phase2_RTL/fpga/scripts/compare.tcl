set board [file normalize [file join [file dirname [info script]] ..]]
set root [file normalize [file join $board ..]]
if {![info exists out]} {set out [file join $root evaluation comparison]}
file mkdir $out
set_param general.maxThreads 2
foreach lanes {1 4} {
  create_project -in_memory -part xc7z020clg400-1
  set f [open [file join $root rtl sources.f] r]
  foreach line [split [read $f] \n] {
    set line [string trim $line]
    if {$line ne ""} {read_verilog -sv [list [file join $root $line]]}
  }
  close $f
  synth_design -top accelerator_top -part xc7z020clg400-1 -mode out_of_context -generic ACTIVATION_LANES=$lanes
  create_clock -name clk -period 40 [get_ports clk]
  report_utilization -file [file join $out lanes${lanes}_area.rpt]
  opt_design
  place_design
  route_design
  report_timing_summary -file [file join $out lanes${lanes}_timing.rpt]
  report_utilization -hierarchical -file [file join $out lanes${lanes}_hierarchy.rpt]
  write_checkpoint -force [file join $out lanes${lanes}_routed.dcp]
  close_project
}
