set board [file normalize [file join [file dirname [info script]] ..]]
if {[info exists ::env(NPU_REPORT_DIR)]} {
  set report_dir [file normalize $::env(NPU_REPORT_DIR)]
} else {
  set report_dir [file join $board reports engineering_closure_20261028]
}
file mkdir $report_dir
set groups [dict create]
foreach cell [get_cells -hier -filter {(REF_NAME == FDRE || REF_NAME == FDSE) && NAME =~ *npu_host*}] {
  if {[string is true -strict [get_property ASYNC_REG $cell]] || [string is true -strict [get_property DONT_TOUCH $cell]]} {continue}
  set key [list [get_property REF_NAME $cell]]
  foreach port {C CE} {lappend key [get_nets -of_objects [get_pins $cell/$port]]}
  if {[get_property REF_NAME $cell] eq "FDSE"} {set port S} else {set port R}
  lappend key [get_nets -of_objects [get_pins $cell/$port]]
  dict lappend groups $key $cell
}
set remapped [list]
dict for {key cells} $groups {
  if {[llength $cells] <= 8} {
    set_property CONTROL_SET_REMAP ALL $cells
    lappend remapped {*}$cells
  }
}
set f [open [file join $report_dir remapped_registers.txt] w]
puts $f "Synchronous NPU FDRE/FDSE groups with eight or fewer registers; ASYNC_REG and DONT_TOUCH excluded"
puts $f [join $remapped \n]
close $f
puts "Applied control-set data remapping to [llength $remapped] synchronous NPU registers"
