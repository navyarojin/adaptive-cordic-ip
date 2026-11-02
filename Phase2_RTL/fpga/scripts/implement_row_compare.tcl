set board [file normalize [file join [file dirname [info script]] ..]]
set work [file join $board work_row_compare]
set reports [file join $board reports row_gating_20261029 compare]
set_param general.maxThreads 2
foreach kind {mac legacy} {
  set dir [file join $reports $kind]
  file mkdir $dir
  create_project -in_memory -part xc7z020clg400-1
  if {$kind eq "mac"} {
    read_verilog -sv [file join $board .. rtl mac.sv]
    read_verilog -sv [file join $work mac_row_compare.sv]
    set top mac_row_compare
  } else {
    foreach source {legacy.sv plain.sv retained.sv zero_hold.sv zero_dual_hold.sv legacy_compare.sv} {
      read_verilog -sv [file join $work legacy $source]
    }
    set top legacy_compare
  }
  synth_design -top $top -part xc7z020clg400-1 -mode out_of_context -flatten_hierarchy none -max_dsp 0
  create_clock -name clk -period 40 [get_ports clk]
  set inputs [get_ports -filter {DIRECTION == IN && NAME != clk}]
  set outputs [get_ports -filter {DIRECTION == OUT}]
  set_input_delay -clock clk -min 20 $inputs
  set_input_delay -clock clk -max 20 $inputs
  set_output_delay -clock clk -min 0 $outputs
  set output_budget [expr {$kind eq "mac" ? 0 : 20}]
  set_output_delay -clock clk -max $output_budget $outputs
  opt_design
  place_design
  phys_opt_design
  route_design
  report_timing_summary -delay_type min_max -report_unconstrained -file [file join $dir timing.rpt]
  report_utilization -hierarchical -file [file join $dir utilization_hierarchical.rpt]
  report_utilization -file [file join $dir utilization.rpt]
  report_clock_utilization -file [file join $dir clock_utilization.rpt]
  foreach delay {min max} {
    if {[llength [get_timing_paths -quiet -delay_type $delay -slack_lesser_than 0 -max_paths 1]]} {error "$kind $delay timing failed"}
  }
  if {[llength [get_cells -hier -filter {REF_NAME =~ BUFG*}]] != 1} {error "Dedicated common clock buffer missing"}
  if {[llength [get_cells -hier -filter {REF_NAME == DSP48E1}]]} {error "Controlled LUT-only comparison inferred DSPs"}
  write_checkpoint -force [file join $dir routed.dcp]
  write_verilog -force -mode timesim -sdf_anno true -sdf_file [file join $dir timing.sdf] [file join $dir timing.v]
  write_sdf -force [file join $dir timing.sdf]
  close_project
}
puts "PASS routed common-clock comparisons with native hierarchical SDF exports"
