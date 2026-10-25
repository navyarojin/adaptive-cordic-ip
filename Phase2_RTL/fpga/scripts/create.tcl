proc src_name {name} {
  set names [dict create pynq_npu_soc soc jupyter_npu host]
  if {[dict exists $names $name]} {return [dict get $names $name]}
  return $name
}
set board [file normalize [file join [file dirname [info script]] ..]]
set root [file normalize [file join $board ..]]
if {![info exists streaming]} {set streaming 0}
if {![info exists out]} {set out [file join $board build_jupyter]}
file mkdir $out
cd $out
set mem [file join $board firmware build_jupyter firmware.mem]
if {$streaming} {set mem [file join $board firmware build_streaming firmware.mem]}
if {![file exists $mem]} { error "Run bash firmware/build.sh jupyter first" }
create_project -force npu_jupyter [file join $out project] -part xc7z020clg400-1
set parts [get_board_parts -quiet *:pynq-z2:part0:*]
if {[llength $parts] == 0} { error "Install the TUL PYNQ-Z2 board files in Vivado" }
set_property board_part [lindex $parts end] [current_project]
set_property target_language Verilog [current_project]
set cpu [file join $board rtl]
set_property include_dirs [list $cpu] [current_fileset]
set f [open [file join $board scripts cpu.flist] r]
foreach line [split [read $f] \n] {
  set line [string trim $line]
  if {[string match {${DESIGN_RTL_DIR}/*} $line] && ![string match {*../*} $line]} {
    read_verilog -sv [list [string map [list {${DESIGN_RTL_DIR}} $cpu] $line]]
  }
}
close $f
set f [open [file join $root rtl sources.f] r]
foreach line [split [read $f] \n] {
  set line [string trim $line]
  if {$line ne ""} { read_verilog -sv [list [file join $root $line]] }
}
close $f
foreach name {cv32e40p_clock_gate host_ram spi_master80 uart_tx pynq_npu_soc jupyter_npu} {
  read_verilog -sv [list [file join $board rtl [src_name $name].sv]]
}
file copy -force $mem [file join $out firmware.mem]
read_verilog [list [file join $board rtl host_bd.v]]
if {$streaming} {read_verilog [list [file join $board rtl stream_bd.v]]}
add_files -norecurse [list [file join $out firmware.mem]]
set_property file_type {Memory Initialization Files} [get_files firmware.mem]
create_bd_design npu_system
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} [get_bd_cells ps7]
set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_EN_CLK0_PORT {1} CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {25.000000}] [get_bd_cells ps7]
if {$streaming} {
  create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_link
  set axi_clock ACLK
  set axi_reset ARESETN
} else {
  create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_link
  set axi_clock aclk
  set axi_reset aresetn
}
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells axi_link]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 mailbox_ctrl
set_property -dict [list CONFIG.DATA_WIDTH {32} CONFIG.SINGLE_PORT_BRAM {1} CONFIG.ECC_TYPE {0}] [get_bd_cells mailbox_ctrl]
if {$streaming} {
  create_bd_cell -type module -reference jupyter_stream_bd npu_host
  if {![info exists stream_lanes]} {set stream_lanes 4}
  set_property CONFIG.STREAM_LANES $stream_lanes [get_bd_cells npu_host]
} else {
  create_bd_cell -type module -reference jupyter_npu_bd npu_host
}
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset_gen
set_property CONFIG.C_AUX_RESET_HIGH 1 [get_bd_cells reset_gen]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 constant_one
set_property CONFIG.CONST_VAL 1 [get_bd_cells constant_one]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 constant_zero
set_property CONFIG.CONST_VAL 0 [get_bd_cells constant_zero]
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi_link/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_link/M00_AXI] [get_bd_intf_pins mailbox_ctrl/S_AXI]
connect_bd_intf_net [get_bd_intf_pins mailbox_ctrl/BRAM_PORTA] [get_bd_intf_pins npu_host/S_BRAM]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK] [get_bd_pins axi_link/$axi_clock] [get_bd_pins mailbox_ctrl/s_axi_aclk] [get_bd_pins reset_gen/slowest_sync_clk] [get_bd_pins npu_host/clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins reset_gen/ext_reset_in]
connect_bd_net [get_bd_pins constant_one/dout] [get_bd_pins reset_gen/dcm_locked]
connect_bd_net [get_bd_pins constant_zero/dout] [get_bd_pins reset_gen/mb_debug_sys_rst]
connect_bd_net [get_bd_pins reset_gen/peripheral_aresetn] [get_bd_pins axi_link/$axi_reset] [get_bd_pins mailbox_ctrl/s_axi_aresetn] [get_bd_pins npu_host/rst_n]
create_bd_port -dir I reset_button
connect_bd_net [get_bd_ports reset_button] [get_bd_pins reset_gen/aux_reset_in]
create_bd_port -dir O -from 3 -to 0 led
connect_bd_net [get_bd_ports led] [get_bd_pins npu_host/led]
create_bd_port -dir O uart_tx
connect_bd_net [get_bd_ports uart_tx] [get_bd_pins npu_host/uart_tx]
assign_bd_address -offset 0x40000000 -range 0x00001000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs mailbox_ctrl/S_AXI/Mem0] -force
if {$streaming} {
  set_property CONFIG.NUM_MI 2 [get_bd_cells axi_link]
  create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 stream_ctrl
  set_property -dict [list CONFIG.DATA_WIDTH {32} CONFIG.SINGLE_PORT_BRAM {1} CONFIG.ECC_TYPE {0}] [get_bd_cells stream_ctrl]
  connect_bd_intf_net [get_bd_intf_pins axi_link/M01_AXI] [get_bd_intf_pins stream_ctrl/S_AXI]
  connect_bd_intf_net [get_bd_intf_pins stream_ctrl/BRAM_PORTA] [get_bd_intf_pins npu_host/S_STREAM]
  connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins stream_ctrl/s_axi_aclk]
  connect_bd_net [get_bd_pins reset_gen/peripheral_aresetn] [get_bd_pins stream_ctrl/s_axi_aresetn]
  assign_bd_address -offset 0x40010000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs stream_ctrl/S_AXI/Mem0] -force
  source [file join $board scripts dma.tcl]
}
validate_bd_design
save_bd_design
set bd [get_files npu_system.bd]
generate_target all $bd
make_wrapper -files $bd -top
set wrapper [file join $out project npu_jupyter.gen sources_1 bd npu_system hdl npu_system_wrapper.v]
add_files -norecurse [list $wrapper]
set_property top npu_system_wrapper [current_fileset]
read_xdc [list [file join $board scripts board.xdc]]
set simulation_top tb_jupyter
if {$streaming} {set simulation_top tb_streaming}
add_files -fileset sim_1 -norecurse [list [file join $root uvm_tb tb ref.sv] [file join $board sim [src_name $simulation_top].sv]]
set_property top $simulation_top [get_filesets sim_1]
set_property top_auto_set 0 [get_filesets sim_1]
set_property xsim.simulate.runtime {300ms} [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Created [file join $out project npu_jupyter.xpr]"
