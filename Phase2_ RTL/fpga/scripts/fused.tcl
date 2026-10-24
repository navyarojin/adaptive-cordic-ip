set board [file normalize [file join [file dirname [info script]] ..]]
set root [file normalize [file join $board ..]]
if {$argc != 1} {error "Supply an output directory for synthesis reports"}
set out [file normalize [lindex $argv 0]]
file mkdir $out
set_param general.maxThreads 2
create_project -in_memory -part xc7z020clg400-1
set f [open [file join $root rtl sources.f] r]
foreach line [split [read $f] \n] {
  set line [string trim $line]
  if {$line ne ""} {read_verilog -sv [list [file join $root $line]]}
}
close $f

synth_design -top stream_mmio -part xc7z020clg400-1 -mode out_of_context -generic LANES=4
create_clock -name clk -period 40 [get_ports clk]
report_utilization -hierarchical -file [file join $out area.rpt]
report_timing_summary -file [file join $out timing.rpt]
write_checkpoint -force [file join $out synthesis.dcp]
close_project
