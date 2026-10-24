set board [file normalize [file join [file dirname [info script]] ..]]
set root [file normalize [file join $board ..]]
if {$argc!=1} {error "Supply report output directory"}
set out [file normalize [lindex $argv 0]]
file mkdir $out
set_param general.maxThreads 2
foreach shared {1 0} {
  set kind [expr {$shared ? "shared" : "independent"}]
  create_project -in_memory -part xc7z020clg400-1
  set f [open [file join $root rtl sources.f] r]
  foreach line [split [read $f] \n] {
    set line [string trim $line]
    if {$line ne ""} {read_verilog -sv [list [file join $root $line]]}
  }
  close $f
  synth_design -top activation_stream_array -part xc7z020clg400-1 -mode out_of_context -generic [list LANES=4 TAG_WIDTH=16 SHARED_REFERENCE=$shared]
  create_clock -name clk -period 40 [get_ports clk]
  set prefix [expr {$shared ? "shared" : "indep"}]
  report_utilization -file [file join $out ${prefix}_area.rpt]
  report_timing_summary -file [file join $out ${prefix}_time.rpt]
  close_project
}
