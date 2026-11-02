set board [file normalize [file join [file dirname [info script]] ..]]
set report [file join $board reports row_gating_20261029]
file mkdir $report
set_param general.maxThreads 2
set checkpoint [file join $report routed.dcp]
if {![file exists $checkpoint]} {set checkpoint [file join $board implementation routed.dcp]}
open_checkpoint $checkpoint
set f [open [file join $report mac_register_enables.csv] w]
puts $f "cell,type,ce_net,constant_ce"
set enabled 0
set total 0
foreach cell [get_cells -hier -filter {NAME =~ *fused_path*mac* && REF_NAME =~ FD*}] {
  set ce [get_pins -quiet $cell/CE]
  if {![llength $ce]} {continue}
  set net [get_nets -quiet -segments -of_objects $ce]
  set drivers [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == OUT}]
  set types [get_property REF_NAME [get_cells -quiet -of_objects $drivers]]
  set constant [expr {[lsearch -exact $types GND] >= 0 || [lsearch -exact $types VCC] >= 0}]
  puts $f "$cell,[get_property REF_NAME $cell],$net,$constant"
  incr total
  if {!$constant} {incr enabled}
}
close $f
if {$total < 500 || $enabled < 500} {error "MAC pipeline enables missing: $enabled of $total registers"}
puts "PASS physical MAC register enables: $enabled nonconstant enables among $total registers"
close_project
