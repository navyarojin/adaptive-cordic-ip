create_library_set -name slow -timing $cfg(lib_max)
create_library_set -name fast -timing $cfg(lib_min)
create_rc_corner -name rcmax -qx_tech_file $cfg(qrc_max) -T $cfg(temp_max)
create_rc_corner -name rcmin -qx_tech_file $cfg(qrc_min) -T $cfg(temp_min)
create_delay_corner -name dc_setup -library_set slow -rc_corner rcmax
create_delay_corner -name dc_hold -library_set fast -rc_corner rcmin
create_constraint_mode -name functional -sdc_files [list [file join $out syn design.sdc]]
create_analysis_view -name setup -constraint_mode functional -delay_corner dc_setup
create_analysis_view -name hold -constraint_mode functional -delay_corner dc_hold
set_analysis_view -setup {setup} -hold {hold}
