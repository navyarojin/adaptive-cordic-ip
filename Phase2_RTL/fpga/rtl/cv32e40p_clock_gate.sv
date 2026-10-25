module cv32e40p_clock_gate (
  input logic clk_i, en_i, scan_cg_en_i,
  output wire clk_o
);
`ifdef SYNTHESIS
  BUFGCE gate_buf (.I(clk_i), .CE(en_i | scan_cg_en_i), .O(clk_o));
`else
  logic enable_latched;
  always_latch if (!clk_i) enable_latched = en_i | scan_cg_en_i;
  assign clk_o = clk_i & enable_latched;
`endif
endmodule
