source [file join [file dirname [info script]] common.tcl]
preflight final_lec
files_exist [list [file join $out syn design.v] [file join $rev_dir design.v]]
set_system_mode setup
read_library -liberty -both {*}$cfg(lib_max)
if {[llength $cfg(lec_models)]} {read_library -verilog -both {*}$cfg(lec_models)}
read_design -verilog -golden [file join $out syn design.v]
read_design -verilog -revised [file join $rev_dir design.v]
set_root_module $cfg(top) -both
report_black_box -detail
set_system_mode lec
add_compared_points -all
compare
report_compared_points
report_unmapped_points
report_verification
exit
