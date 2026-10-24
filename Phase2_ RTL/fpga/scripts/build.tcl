source [file join [file dirname [info script]] create.tcl]
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed" }
launch_runs impl_1 -to_step route_design -jobs 2
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Implementation failed" }
open_run impl_1
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out time.rpt]
report_drc -file [file join $out drc.rpt]
report_cdc -file [file join $out cdc.rpt]
report_utilization -file [file join $out area.rpt]
report_power -file [file join $out power.rpt]
foreach kind {max min} {
  if {[llength [get_timing_paths -quiet -delay_type $kind -slack_lesser_than 0 -max_paths 1]]} { error "$kind timing failed" }
}
set bundle [file join $board jupyter]
if {$streaming} {set bundle [file join $board jupyter_streaming]}
if {$streaming && $stream_lanes==1} {set bundle [file join $board jupyter_streaming_lane1]}
file mkdir $bundle
write_bitstream -force [file join $bundle board.bit]
set hwh [file join $out project npu_jupyter.gen sources_1 bd npu_system hw_handoff npu_system.hwh]
if {![file exists $hwh]} { error "HWH export missing: $hwh" }
file copy -force $hwh [file join $bundle board.hwh]
foreach name {client.py stream.py npu.ipynb stream.ipynb run.py bench.py} {
    if {[file normalize $bundle] ne [file normalize [file join $board jupyter_streaming]]} {
      file copy -force [file join $board jupyter_streaming $name] [file join $bundle $name]
    }
  }
if {$streaming} {
  file copy -force [file join $root evaluation data model.json] [file join $bundle model.json]
}
puts "Upload the files in $bundle to one directory on the PYNQ board"
