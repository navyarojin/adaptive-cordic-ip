set board [file normalize [file join [file dirname [info script]] ..]]
set work [file join $board work_isolation]
set report_dir [file join $board reports isolation_hold_20261028]
set_param general.maxThreads 2
set timing_only [expr {[llength $argv] && [lindex $argv 0] eq "--timing-only"}]
set power_cases {0 1 2 3 4 5 6 7}
if {[lsearch -exact $argv --fixed-only] >= 0} {set power_cases {0 1 2 3}}
foreach variant {legacy plain retained isolated dual} {
  set variant_dir [file join $report_dir $variant]
  if {$timing_only && [file exists [file join $variant_dir internal_setup.rpt]] && [file exists [file join $variant_dir internal_hold.rpt]]} {continue}
  open_checkpoint [file join $variant_dir routed.dcp]
  set registers [all_registers -clock clk]
  set timing_file [open [file join $variant_dir internal_timing.txt] w]
  foreach {kind label} {max setup min hold} {
    set paths [get_timing_paths -from $registers -to $registers -delay_type $kind -max_paths 1]
    puts $timing_file "$label [get_property SLACK $paths]"
    report_timing -from $registers -to $registers -delay_type $kind -max_paths 1 -file [file join $variant_dir internal_${label}.rpt]
    if {[llength [get_timing_paths -quiet -from $registers -to $registers -delay_type $kind -slack_lesser_than 0 -max_paths 1]]} {error "Internal $label timing failed: $variant"}
  }
  close $timing_file
  if {$timing_only} {close_project; continue}
  foreach case $power_cases {
    set trace_dir [file join $work phy_case_$case]
    set trace_log [file join $trace_dir run.log]
    set ready 0
    for {set attempt 0} {$attempt < 600} {incr attempt} {
      if {[file exists $trace_log] && [file mtime $trace_log] >= [file mtime [file join $work provenance.json]]} {
        set log_handle [open $trace_log r]
        set log_text [read $log_handle]
        close $log_handle
        if {[regexp {Fatal:|Error:|[Tt]iming violation} $log_text]} {error "Timing trace failed: $case"}
        if {[string first "PASS isolation: jobs=64 checked_rows_across_variants=1280 latency_min=8 latency_max=8 case=$case" $log_text] >= 0 && [string first "Exiting xsim" $log_text] >= 0} {set ready 1; break}
      }
      if {$attempt == 0} {puts "Waiting for completed timing trace: $case"}
      after 1000
    }
    if {!$ready} {error "No completed current-run timing trace: $case"}
    reset_switching_activity -all
    set case_dir [file join $variant_dir case_$case]
    file mkdir $case_dir
    read_saif -strip_path tb_isolation/$variant -out_file [file join $case_dir annotation.txt] [file join $work phy_case_$case activity.saif]
    report_power -file [file join $case_dir power.rpt]
    report_power -format xml -file [file join $case_dir power.xml]
  }
  close_project
}
if {$timing_only} {puts "PASS internal timing audits"} else {puts "PASS SDF-activity-based isolated MAC power estimates"}
