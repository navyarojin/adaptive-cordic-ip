set pdk /home/Student/sclpdk_new/SCLPDK_V3.0_KIT/scl180
if {[info exists ::env(SCL_PDK)] && $::env(SCL_PDK) ne ""} {
    set pdk $::env(SCL_PDK)
}
set cells [file join $pdk stdcell fs120 6M1L]
set cfg(top) stream_mmio
set cfg(period) 40.0
set cfg(lib_max) [list [file join $cells liberty lib_flow_ss tsl18fs120_scl_ss.lib]]
set cfg(lib_min) [list [file join $cells liberty lib_flow_ff tsl18fs120_scl_ff.lib]]
set cfg(lef) [list [file join $cells lef scl18fs120_tech.lef] [file join $cells lef scl18fs120_std.lef]]
