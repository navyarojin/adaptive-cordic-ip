source [file join [file dirname [info script]] common.tcl]
set stage $::env(ASIC_STAGE)
preflight $stage
file mkdir [file join $out pnr]
proc load_step {name} {
    global out cfg
    set db [file join $out pnr ${name}.enc]
    files_exist [list $db]
    restoreDesign $db $cfg(top)
}
proc export_layout {directory} {
    global cfg
    file mkdir $directory
    saveDesign [file join $directory design.enc]
    saveNetlist [file join $directory design.v]
    if {$cfg(top) eq "chip"} {
        saveNetlist [file join $directory power.v] -phys -includePowerGround -includePhysicalInst
    } else {
        saveNetlist [file join $directory power.v] -includePowerGround
    }
    defOut -floorplan -netlist -routing [file join $directory design.def]
    streamOut [file join $directory design.gds] -mapFile $cfg(gds_map) -merge $cfg(gds_cells) -mode ALL
}
switch -- $stage {
    floor {
        files_exist [list [file join $out syn design.v] [file join $out syn design.sdc]]
        set init_top_cell $cfg(top)
        set init_verilog [file join $out syn design.v]
        set init_lef_file $cfg(lef)
        set init_pwr_net $cfg(power)
        set init_gnd_net $cfg(ground)
        if {$cfg(top) eq "chip"} {
            set init_pwr_net [list $cfg(power) $cfg(io_power)]
            set init_gnd_net [list $cfg(ground) $cfg(io_ground)]
        }
        set view_file [file join $out pnr views.tcl]
        set fd [open $view_file w]
        puts $fd [list source [file join $flow_dir common.tcl]]
        puts $fd [list source [file join $flow_dir views.tcl]]
        close $fd
        set init_mmmc_file $view_file
        init_design
        if {$cfg(top) eq "chip"} {
            hook pad_floor_hook
            source [file join $asic_dir pads place.tcl]
        } else {
            floorPlan -site $cfg(site) -r $cfg(aspect) $cfg(density) $cfg(margin) $cfg(margin) $cfg(margin) $cfg(margin)
            hook floor_hook
        }
    }
    power {
        load_step floor
        if {$cfg(top) eq "chip"} {
            hook pad_power_hook
        } else {
            globalNetConnect $cfg(power) -type pgpin -pin $cfg(power_pin) -inst *
            globalNetConnect $cfg(ground) -type pgpin -pin $cfg(ground_pin) -inst *
            set nets [list $cfg(power) $cfg(ground)]
            addRing -nets $nets -type core_rings -follow core -layer [list top $cfg(ring_h) bottom $cfg(ring_h) left $cfg(ring_v) right $cfg(ring_v)] -width $cfg(ring_width) -spacing $cfg(ring_spacing) -offset $cfg(ring_offset)
            addStripe -nets $nets -layer $cfg(stripe_layer) -direction vertical -width $cfg(stripe_width) -spacing $cfg(ring_spacing) -set_to_set_distance $cfg(stripe_pitch)
            sroute -nets $nets -connect {corePin blockPin floatingStripe}
        }
    }
    place {
        load_step power
        placeDesign
        optDesign -preCTS
        timeDesign -preCTS -outDir [file join $out pnr place_timing]
    }
    cts {
        load_step place
        set_ccopt_property buffer_cells $cfg(cts_buffers)
        set_ccopt_property inverter_cells $cfg(cts_inverters)
        set_ccopt_property target_max_trans $cfg(cts_transition)
        set_ccopt_property target_skew $cfg(cts_skew)
        create_ccopt_clock_tree_spec
        ccopt_design
        optDesign -postCTS
        optDesign -postCTS -hold
        timeDesign -postCTS -outDir [file join $out pnr cts_timing]
        report_ccopt_clock_trees -file [file join $out pnr clocks.rpt]
    }
    route {
        load_step cts
        setNanoRouteMode -routeBottomRoutingLayer $cfg(route_bottom)
        setNanoRouteMode -routeTopRoutingLayer $cfg(route_top)
        setNanoRouteMode -routeWithTimingDriven true
        setNanoRouteMode -drouteFixAntenna true
        routeDesign
        optDesign -postRoute
        optDesign -postRoute -hold
        hook finish_hook
        verifyGeometry -report [file join $out pnr geometry.rpt]
        verifyConnectivity -type all -report [file join $out pnr connectivity.rpt]
        verifyProcessAntenna -reportfile [file join $out pnr antenna.rpt]
        export_layout [file join $out route]
    }
    eco {
        files_exist [list [file join $out route design.enc]]
        restoreDesign [file join $out route design.enc] $cfg(top)
        hook eco_hook
        ecoRoute
        hook finish_hook
        export_layout [file join $out eco]
        puts "ECO exported. Repeat PEX, STA, post-GLS, DRC, ARC, LVS and final LEC with ASIC_REV=eco."
    }
    default {error "Unsupported PNR stage: $stage"}
}
saveDesign [file join $out pnr ${stage}.enc]
puts "Checkpoint written for $stage; tool completion is not timing or physical sign-off."
exit
