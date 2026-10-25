module zero_aware_systolic_npu (
  input logic clk, rst_n, clear_i, load_weights_i,
  input logic signed [127:0] weights_i,
  input logic in_valid_i,
  input logic signed [31:0] activations_i,
  output logic ready_o, out_valid_o,
  output logic signed [95:0] accumulations_o
);
  zero_aware_systolic_npu_param #(.ARRAY_DIM(4)) u_array (
    .clk, .rst_n, .clear_i, .load_weights_i, .weights_i,
    .in_valid_i, .activations_i, .ready_o, .out_valid_o, .accumulations_o
  );
endmodule
