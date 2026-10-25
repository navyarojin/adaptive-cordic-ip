source [file join [file dirname [info script]] common.tcl]
preflight lint
set rtl_sources [source_list]
file mkdir [file join $out lint]
clear -all
if {$cfg(top) eq "chip"} {analyze -sv {*}$cfg(pad_models)}
analyze -sv {*}$rtl_sources
elaborate -top $cfg(top)
clock $cfg(clock)
reset -expression "!$cfg(reset)"
hook lint_hook
puts "Lint adapter completed; the launcher also requires the configured lint report checker."
exit
