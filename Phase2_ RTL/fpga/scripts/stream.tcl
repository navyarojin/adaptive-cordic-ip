set streaming 1
set out [file normalize [file join [file dirname [info script]] .. reports build_streaming_parallel]]
source [file join [file dirname [info script]] create.tcl]
