set stream_lanes 1
set out [file normalize [file join [file dirname [info script]] .. reports build_streaming_axi]]
source [file join [file dirname [info script]] check_dma.tcl]
