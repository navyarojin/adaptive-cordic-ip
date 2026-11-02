set board [file normalize [file join [file dirname [info script]] ..]]
set_param general.maxThreads 2
foreach kind {mac legacy} {
  set dir [file join $board reports row_gating_20261029 compare $kind]
  open_checkpoint [file join $dir routed.dcp]
  write_verilog -force -mode timesim -sdf_anno true -sdf_file [file join $dir timing.sdf] [file join $dir timing.v]
  write_sdf -force [file join $dir timing.sdf]
  write_verilog -force -mode funcsim [file join $dir functional.v]
  close_project
}
puts "PASS netlist-first native SDF exports from unchanged routed checkpoints"
source [file join $board scripts audit_row_gating.tcl]
