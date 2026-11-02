module mac_row_compare (
  input logic clk,rst_n,valid_i,ready_i,
  input logic [31:0] values_i,
  input logic [127:0] weights_i,bias_i,
  input logic [3:0] row_active_i,
  input logic [4:0] shift_i,
  input logic [15:0] tag_i,
  output wire [1:0] ready_o,valid_o,idle_o,
  output wire [151:0] values_o,
  output wire [31:0] tag_o
);
  wire core_clk;
  BUFG clock_buffer(.I(clk),.O(core_clk));
  (* KEEP_HIERARCHY="yes" *) mac4_stream #(.TAG_WIDTH(16),.ENABLE_GATING(1)) gated (
    .clk(core_clk),.rst_n,.valid_i,.ready_i,.values_i,.weights_i,.bias_i,.row_active_i,.shift_i,.tag_i,
    .ready_o(ready_o[0]),.valid_o(valid_o[0]),.idle_o(idle_o[0]),.values_o(values_o[75:0]),.tag_o(tag_o[15:0]));
  (* KEEP_HIERARCHY="yes" *) mac4_stream #(.TAG_WIDTH(16),.ENABLE_GATING(0)) ungated (
    .clk(core_clk),.rst_n,.valid_i,.ready_i,.values_i,.weights_i,.bias_i,.row_active_i,.shift_i,.tag_i,
    .ready_o(ready_o[1]),.valid_o(valid_o[1]),.idle_o(idle_o[1]),.values_o(values_o[151:76]),.tag_o(tag_o[31:16]));
endmodule
