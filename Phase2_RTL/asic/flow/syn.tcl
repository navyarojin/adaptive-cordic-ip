source [file join [file dirname [info script]] common.tcl]
preflight syn
file mkdir [file join $out syn]
cd [file join $out syn]
set_db init_hdl_search_path [list [file join $rtl_dir rtl]]
read_libs $cfg(lib_max)
read_hdl -sv [source_list]
elaborate $cfg(top)
check_design -unresolved
if {$cfg(top) eq "chip"} {
    set_db auto_ungroup none
    set pads [get_db insts */pad_*]
    if {[llength $pads]!=170} {error "Expected 170 bound signal-pad cells before synthesis"}
    set_db $pads .preserve true
}
read_sdc [file join $flow_dir constraints.sdc]
set_db syn_generic_effort medium
set_db syn_map_effort medium
set_db syn_opt_effort medium
syn_generic
syn_map
write_do_lec -golden_design rtl -revised_design fv_map > rtl_map.do
syn_opt
write_hdl > design.v
write_do_lec -golden_design fv_map -revised_design [file join $out syn design.v] > map_syn.do
write_sdc > design.sdc
write_sdf > design.sdf
report_area > area.rpt
report_timing > timing.rpt
report_power > power.rpt
report_gates > gates.rpt
puts "Synthesis outputs: [pwd]. Review unresolved cells, timing, latches and mapping reports."
exit
