set board [file normalize [file join [file dirname [info script]] ..]]
set root [file normalize [file join $board ..]]
set out [file join $board reports stream_shared_verify]
file mkdir $out
set_param general.maxThreads 2
create_project -in_memory -part xc7z020clg400-1
set f [open [file join $root rtl sources.f] r]
foreach line [split [read $f] \n] {
  set line [string trim $line]
  if {$line ne ""} {read_verilog -sv [list [file join $root $line]]}
}
close $f
synth_design -top stream_job_engine -part xc7z020clg400-1 -mode out_of_context -generic LANES=4
create_clock -name clk -period 40 [get_ports clk]
report_utilization -hierarchical -file [file join $out synthesis_area.rpt]
write_checkpoint -force [file join $out synthesis.dcp]
close_project
