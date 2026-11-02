
set board [file normalize [file join [file dirname [info script]] ..]]
if {![info exists audit_out]} {set audit_out [file join $board reports audit_latest]}
file mkdir $audit_out
set project_file [file join $board reports build_streaming_parallel project npu_jupyter.xpr]
set current_checkpoint [file join $board implementation routed.dcp]
set closure_checkpoint [file join $board reports engineering_closure_20261028 routed.dcp]
if {[file exists $current_checkpoint]} {
  open_checkpoint $current_checkpoint
} elseif {[file exists $closure_checkpoint]} {
  open_checkpoint $closure_checkpoint
} elseif {[file exists $project_file]} {
  open_project $project_file
  open_run impl_1
} else {
  open_checkpoint [file join $board reports build_streaming_parallel routed.dcp]
}
set f [open [file join $audit_out drc_check_properties.txt] w]
puts $f [list_property [get_drc_checks REQP-1839]]
close $f
if {![info exists drc_detail_limit]} {set drc_detail_limit 200}
foreach check [get_drc_checks] {
  foreach property {MAX_MESSAGES MAX_NAMES} {
    if {[lsearch -exact [list_property $check] $property] >= 0} {set_property $property $drc_detail_limit $check}
  }
}
if {[lsearch -exact $argv drc-only] >= 0} {
  report_drc -file [file join $audit_out drc_expanded.rpt]
  puts "Expanded DRC report generated with per-check detail limit $drc_detail_limit; CHECK-3 means the total remains truncated"
  close_project
  exit
}
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $audit_out timing.rpt]
check_timing -verbose -file [file join $audit_out check_timing.rpt]
report_drc -file [file join $audit_out drc.rpt]
report_methodology -file [file join $audit_out methodology.rpt]
report_cdc -details -file [file join $audit_out cdc.rpt]
report_utilization -hierarchical -file [file join $audit_out utilization_hierarchical.rpt]
report_utilization -file [file join $audit_out utilization.rpt]
report_power -file [file join $audit_out power_vectorless.rpt]
report_exceptions -file [file join $audit_out exceptions.rpt]
foreach kind {max min} {
  if {[llength [get_timing_paths -quiet -delay_type $kind -slack_lesser_than 0 -max_paths 1]]} {error "$kind timing failed"}
}
puts "PASS routed FPGA audit: timing, DRC, CDC, methodology, exceptions, utilization and vectorless power reports refreshed"
close_project
