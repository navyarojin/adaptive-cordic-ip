set streaming 1
set stream_lanes 4
set out [file normalize [file join [file dirname [info script]] .. reports build_streaming_parallel]]
source [file join [file dirname [info script]] build.tcl]
