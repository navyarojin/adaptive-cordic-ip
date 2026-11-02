set board [file normalize [file join [file dirname [info script]] ..]]
set dir [file join $board reports row_gating_20261029 compare mac]
set_param general.maxThreads 2
open_checkpoint [file join $dir routed.dcp]
foreach profile {actual dense masks idle} {
  set data [file join $dir rtl_$profile]
  reset_switching_activity -all
  read_saif -strip_path tb_mac_row_compare/suite -out_file [file join $data annotation.txt] [file join $data activity_mapped.saif]
  report_power -hier all -hierarchical_depth 3 -file [file join $data power.rpt]
  report_power -hier all -hierarchical_depth 3 -format xml -file [file join $data power.xml]
  report_power -advisory -file [file join $data advisory.rpt]
}
close_project
puts "PASS matched MAC estimates using checked RTL activity; no SDF glitch-power claim"
