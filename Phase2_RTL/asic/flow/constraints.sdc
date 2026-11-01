if {![info exists cfg(period)]} {error "Source flow/common.tcl before constraints.sdc"}
create_clock -name core_clk -period $cfg(period) [get_ports $cfg(clock)]
set_clock_uncertainty $cfg(uncertainty) [get_clocks core_clk]
set_clock_transition $cfg(transition) [get_clocks core_clk]
set data_inputs [remove_from_collection [all_inputs] [get_ports $cfg(clock)]]
set_input_delay -max $cfg(input_delay) -clock core_clk $data_inputs
set_input_delay -min 0.0 -clock core_clk $data_inputs
set_input_transition $cfg(transition) $data_inputs
set_output_delay -max $cfg(output_delay) -clock core_clk [all_outputs]
set_output_delay -min 0.0 -clock core_clk [all_outputs]
set_load $cfg(load) [all_outputs]
