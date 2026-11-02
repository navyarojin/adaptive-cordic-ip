set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {4}] [get_bd_cells axi_link]
foreach port {S00 S01 M00 M01 M02 M03} {
  connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_link/${port}_ACLK]
  connect_bd_net [get_bd_pins reset_gen/peripheral_aresetn] [get_bd_pins axi_link/${port}_ARESETN]
}
set_property -dict [list CONFIG.PCW_USE_S_AXI_HP0 {1} CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64}] [get_bd_cells ps7]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_cdma:4.1 stream_dma
set_property -dict [list CONFIG.C_INCLUDE_SG {0} CONFIG.C_INCLUDE_DRE {0} CONFIG.C_M_AXI_DATA_WIDTH {32} CONFIG.C_M_AXI_MAX_BURST_LEN {16}] [get_bd_cells stream_dma]
connect_bd_intf_net [get_bd_intf_pins stream_dma/M_AXI] [get_bd_intf_pins axi_link/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_link/M02_AXI] [get_bd_intf_pins stream_dma/S_AXI_LITE]
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 hp_bridge
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells hp_bridge]
connect_bd_intf_net [get_bd_intf_pins axi_link/M03_AXI] [get_bd_intf_pins hp_bridge/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins hp_bridge/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP0]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins hp_bridge/aclk]
connect_bd_net [get_bd_pins reset_gen/peripheral_aresetn] [get_bd_pins hp_bridge/aresetn]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins stream_dma/m_axi_aclk] [get_bd_pins stream_dma/s_axi_lite_aclk] [get_bd_pins ps7/S_AXI_HP0_ACLK]
connect_bd_net [get_bd_pins reset_gen/peripheral_aresetn] [get_bd_pins stream_dma/s_axi_lite_aresetn]
assign_bd_address -offset 0x40400000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs stream_dma/S_AXI_LITE/Reg] -force
assign_bd_address -offset 0x00000000 -range 0x20000000 -target_address_space [get_bd_addr_spaces stream_dma/Data] [get_bd_addr_segs ps7/S_AXI_HP0/HP0_DDR_LOWOCM] -force
assign_bd_address -offset 0x40010000 -range 0x00010000 -target_address_space [get_bd_addr_spaces stream_dma/Data] [get_bd_addr_segs stream_ctrl/S_AXI/Mem0] -force
exclude_bd_addr_seg -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs ps7/S_AXI_HP0/HP0_DDR_LOWOCM]
exclude_bd_addr_seg -target_address_space [get_bd_addr_spaces stream_dma/Data] [get_bd_addr_segs mailbox_ctrl/S_AXI/Mem0]
exclude_bd_addr_seg -target_address_space [get_bd_addr_spaces stream_dma/Data] [get_bd_addr_segs stream_dma/S_AXI_LITE/Reg]
