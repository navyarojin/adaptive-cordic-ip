set board [file normalize [file join [file dirname [info script]] ..]]
if {![info exists report_dir]} {set report_dir [file join $board reports engineering_closure_20261028]}
open_checkpoint [file join $report_dir routed.dcp]
report_drc -checks [get_drc_checks REQP-1839] -file [file join $report_dir reset_drc.rpt]
if {[llength [get_drc_violations -quiet REQP-1839*]]} {error "Asynchronous BRAM control paths remain"}
report_methodology -checks [get_methodology_checks {LUTAR-1 DPIR-1 ULMTCS-1}] -file [file join $report_dir reset_control_methodology.rpt]
check_timing -verbose -file [file join $report_dir check_timing.rpt]
set f [open [file join $report_dir dsp_path_review.csv] w]
puts $f "cell,category,AREG,BREG,MREG,PREG,worst_output_slack_ns"
set index 0
foreach cell [lsort [get_cells -hier -filter {REF_NAME == DSP48E1}]] {
  if {[string match *reconstruct* $cell]} {
    set category streaming_square
    foreach property {AREG BREG MREG PREG} {
      if {[get_property $property $cell] < 1} {error "Missing $property on streaming multiplier $cell"}
    }
  } elseif {[string match *cpu*mult_i* $cell]} {
    set category cpu_fixed_instruction_latency
  } elseif {[string match *u_cordic_core*u_mul* $cell]} {
    set category legacy_fixed_fsm_latency
  } elseif {[string match *fused_path/mac/* $cell]} {
    set category streaming_mac_four_stage_latency
  } else {
    error "Unreviewed DSP $cell"
  }
  set pins [get_pins -of_objects $cell -filter {DIRECTION == OUT && REF_PIN_NAME =~ P*}]
  set paths [get_timing_paths -through $pins -delay_type max -max_paths 1]
  if {![llength $paths]} {error "No timed output path for $cell"}
  set slack [get_property SLACK [lindex $paths 0]]
  if {$slack < 0} {error "DSP timing failed: $cell"}
  puts $f [join [list $cell $category [get_property AREG $cell] [get_property BREG $cell] [get_property MREG $cell] [get_property PREG $cell] $slack] ,]
  report_timing -through $pins -delay_type max -max_paths 1 -file [file join $report_dir dsp_path_${index}.rpt]
  incr index
}
close $f
foreach kind {max min} {
  if {[llength [get_timing_paths -quiet -delay_type $kind -slack_lesser_than 0 -max_paths 1]]} {error "$kind timing failed"}
}
puts "PASS engineering audit: asynchronous BRAM controls cleared, streaming DSP stages checked, all DSP output paths meet timing"
close_project
