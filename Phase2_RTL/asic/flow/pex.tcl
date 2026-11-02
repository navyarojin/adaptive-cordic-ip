source [file join [file dirname [info script]] common.tcl]
preflight pex
files_exist [list [file join $rev_dir design.enc]]
file mkdir [file join $rev_dir pex]
restoreDesign [file join $rev_dir design.enc] $cfg(top)
setExtractRCMode -engine postRoute -effortLevel signoff -coupled true
extractRC
rcOut -rc_corner rcmax -spef [file join $rev_dir pex max.spef]
rcOut -rc_corner rcmin -spef [file join $rev_dir pex min.spef]
puts "Quantus extraction outputs: [file join $rev_dir pex]. Review extraction coverage and warnings."
exit
