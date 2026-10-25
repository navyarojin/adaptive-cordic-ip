source [file join [file dirname [info script]] common.tcl]
preflight sta
files_exist [list [file join $rev_dir design.v] [file join $rev_dir pex max.spef] [file join $rev_dir pex min.spef] [file join $out syn design.sdc]]
file mkdir [file join $rev_dir sta]
read_view_definition [file join $flow_dir views.tcl]
read_verilog [file join $rev_dir design.v]
set_top_module $cfg(top)
read_spef -rc_corner rcmax [file join $rev_dir pex max.spef]
read_spef -rc_corner rcmin [file join $rev_dir pex min.spef]
set_propagated_clock [all_clocks]
hook sta_hook
update_timing
check_timing > [file join $rev_dir sta checks.rpt]
report_timing -late -max_paths 100 > [file join $rev_dir sta setup.rpt]
report_timing -early -max_paths 100 > [file join $rev_dir sta hold.rpt]
report_constraint -all_violators > [file join $rev_dir sta limits.rpt]
write_sdf -max_view setup -min_view hold [file join $rev_dir sta design.sdf]
puts "Review all views, unconstrained paths, annotation, recovery/removal and violations in [file join $rev_dir sta]."
exit
