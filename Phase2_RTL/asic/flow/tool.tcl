set directory [file dirname [info script]]
set stage $::env(ASIC_STAGE)
switch -- $stage {
    syn {set script syn.tcl}
    lint {set script lint.tcl}
    floor - power - place - cts - route - eco {set script pnr.tcl}
    pex {set script pex.tcl}
    sta {set script sta.tcl}
    default {puts stderr "Unsupported tool stage: $stage"; exit 2}
}
if {[catch {source [file join $directory $script]} message]} {
    puts stderr "ASIC stage $stage failed: $message"
    exit 2
}
