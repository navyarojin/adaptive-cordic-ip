`include "params.vh"
`include "sigmoid.v"
module published_sigmoid_benchmark (
  input logic clk,rst_n,valid_i,
  input logic signed [15:0] x_i,
  output logic valid_o,
  output wire signed [15:0] y_o
);
  logic signed [15:0] x_q;
  logic valid_q;
  sigmoid baseline(.ck(clk),.x(x_q),.y(y_o));
  always_ff @(posedge clk) begin
    x_q<=x_i;
    if (!rst_n) begin valid_q<=0; valid_o<=0; end
    else begin valid_q<=valid_i; valid_o<=valid_q; end
  end
endmodule
module cordic_sigmoid_benchmark (
  input logic clk,rst_n,valid_i,
  input logic signed [15:0] x_i,
  output logic valid_o,
  output logic signed [15:0] y_o
);
  wire signed [15:0] value_q14;
  logic signed [15:0] x_q;
  logic valid_q;
  wire valid_mid;
  wire signed [18:0] scaled_input=19'($signed(x_q))<<<2;
  cordic_activation_stream arithmetic (
    .clk,.rst_n,.valid_i(valid_q),.ready_o(),.value_i(scaled_input),.mode_i(2'd1),
    .iterations_i(5'd14),.rounding_i(1'b1),.tag_i(1'b0),
    .valid_o(valid_mid),.ready_i(1'b1),.result_o(value_q14),.tag_o());
  always_ff @(posedge clk) begin
    x_q<=x_i;
    y_o<=16'((17'($signed(value_q14))+17'sd2)>>>2);
    if (!rst_n) begin valid_q<=0; valid_o<=0; end
    else begin valid_q<=valid_i; valid_o<=valid_mid; end
  end
endmodule
