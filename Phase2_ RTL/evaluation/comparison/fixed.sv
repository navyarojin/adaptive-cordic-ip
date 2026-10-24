module fixed_activation_baseline (
  input logic clk,rst_n,valid_i,
  output wire ready_o,
  input logic [75:0] values_i,
  input logic [1:0] mode_i,
  input logic [15:0] tag_i,
  output wire valid_o,
  input logic ready_i,
  output wire [63:0] results_o,
  output wire [15:0] tag_o
);
  wire [3:0] ready,valid;
  wire [15:0] tags [0:3];
  assign ready_o=&ready;
  assign valid_o=&valid;
  assign tag_o=tags[0];
  for(genvar l=0;l<4;l++) begin : lanes
    cordic_activation_stream #(.TAG_WIDTH(16)) pipe (
      .clk,.rst_n,.valid_i(valid_i && ready_o),.ready_o(ready[l]),
      .value_i(values_i[l*19 +: 19]),.mode_i,.iterations_i(5'd14),.rounding_i(1'b1),.tag_i,
      .valid_o(valid[l]),.ready_i(ready_i && valid_o),.result_o(results_o[l*16 +: 16]),.tag_o(tags[l]));
  end
endmodule
