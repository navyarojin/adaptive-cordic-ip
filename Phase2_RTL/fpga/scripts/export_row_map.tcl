set board [file normalize [file join [file dirname [info script]] ..]]
set dir [file join $board reports row_gating_20261029 compare]
set_param general.maxThreads 2
open_checkpoint [file join $dir mac routed.dcp]
set f [open [file join $dir register_activity_map.csv] w]
puts $f "rtl_signal,routed_signal"
set count 0
foreach cell [get_cells -hier -filter {REF_NAME =~ FD*}] {
  if {![regexp {^(gated|ungated)/(.+)_reg((?:\[[0-9]+\])+)$} $cell unused scope base indices]} {continue}
  set source $scope/$base$indices
  foreach net [get_nets -quiet -of_objects [get_pins -quiet $cell/Q]] {
    if {![string match $scope/* $net]} {continue}
    puts $f "$source,$net"
    incr count
  }
}
close $f
if {$count < 1000} {error "Insufficient exact register-name mappings: $count"}
puts "PASS exported $count exact RTL-register to routed-Q-net mappings"
close_project
