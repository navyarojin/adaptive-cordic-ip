if {$cfg(top) ne "chip"} {error "Pad placement requires top=chip"}
if {!$cfg(pad_ring_verified)} {error "Approve a PDK/package-specific complete pad ring before placement"}
hook pad_physical_hook
files_exist [list $cfg(pad_io)]
set fd [open [file join $asic_dir pads map.csv] r]
gets $fd header
set expected {}
while {[gets $fd row]>=0} {
    set columns [split [string trim $row] ,]
    if {[llength $columns]==4} {lappend expected [lindex $columns 3]}
}
close $fd
if {[llength $expected]!=170} {error "Signal pad inventory must contain 170 entries"}
if {[llength $cfg(pad_corner_instances)]!=4} {error "Four verified corner instances are required"}
set fd [open $cfg(pad_io) r]
set text [read $fd]
close $fd
set placed {}
foreach {match name} [regexp -all -inline {name\s*=\s*"([^"]+)"} $text] {lappend placed $name}
if {[llength $placed]!=[llength [lsort -unique $placed]]} {error "Duplicate instance names in pad IO assignment"}
foreach name [concat $expected $cfg(pad_supply_instances) $cfg(pad_corner_instances)] {
    if {[lsearch -exact $placed $name]<0} {error "Pad missing from approved IO assignment: $name"}
}
set actual [dbGet top.insts.name]
foreach name [concat $expected $cfg(pad_supply_instances) $cfg(pad_corner_instances)] {
    if {[lsearch -exact $actual $name]<0} {error "Missing pad/ring instance in Innovus: $name"}
}
loadIoFile $cfg(pad_io)
foreach name [concat $expected $cfg(pad_supply_instances) $cfg(pad_corner_instances)] {
    dbSet [dbGet top.insts.name $name -p].pStatus fixed
}
puts "Loaded approved pad placement. Review orientations, edge pitch, bond access and rail continuity."
