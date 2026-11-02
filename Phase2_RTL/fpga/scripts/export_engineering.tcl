set board [file normalize [file join [file dirname [info script]] ..]]
if {![info exists report_dir]} {set report_dir [file join $board reports engineering_closure_20261028]}
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $report_dir timing.rpt]
report_drc -file [file join $report_dir drc.rpt]
report_methodology -file [file join $report_dir methodology.rpt]
report_cdc -details -file [file join $report_dir cdc.rpt]
report_control_sets -verbose -file [file join $report_dir control_sets.rpt]
report_utilization -hierarchical -file [file join $report_dir utilization_hierarchical.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_power -file [file join $report_dir power_vectorless.rpt]
report_exceptions -file [file join $report_dir exceptions.rpt]
set f [open [file join $report_dir dsp_registers.csv] w]
puts $f "cell,AREG,BREG,MREG,PREG"
foreach cell [lsort [get_cells -hier -filter {REF_NAME == DSP48E1}]] {
  puts $f [join [list $cell [get_property AREG $cell] [get_property BREG $cell] [get_property MREG $cell] [get_property PREG $cell]] ,]
}
close $f
set f [open [file join $report_dir target_checks.rpt] w]
foreach rule {REQP-1839} {
  set violations [get_drc_violations -quiet ${rule}*]
  puts $f "$rule [llength $violations]"
}
close $f
foreach kind {max min} {
  if {[llength [get_timing_paths -quiet -delay_type $kind -slack_lesser_than 0 -max_paths 1]]} {error "$kind timing failed"}
}
write_checkpoint -force [file join $report_dir routed.dcp]
set candidate [file join $report_dir candidate]
file mkdir $candidate
write_bitstream -force [file join $candidate board.bit]
file copy -force [file join $out project npu_jupyter.gen sources_1 bd npu_system hw_handoff npu_system.hwh] [file join $candidate board.hwh]
puts "PASS fresh routed candidate and implementation reports: $candidate"
