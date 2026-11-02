set board [file normalize [file join [file dirname [info script]] ..]]
set out [file join $board work_row_gating]
source [file join $board scripts check_dma.tcl]
puts "PASS row-gating vendor AXI DMA regression"
close_project
