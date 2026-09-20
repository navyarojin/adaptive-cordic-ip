module zero_aware_systolic_npu (
  input logic clk,
  input logic rst_n,
  input logic clear_i,
  input logic load_weights_i,
  input logic signed [127:0] weights_i,
  input logic in_valid_i,
  input logic signed [31:0] activations_i,
  output logic ready_o,
  output logic out_valid_o,
  output logic signed [95:0] accumulations_o
);
  logic signed [7:0] weights_q [0:3][0:3];
  logic signed [7:0] activations_q [0:3];
  logic signed [7:0] a_pipe [0:3][0:3];
  logic signed [23:0] partial_q [0:3][0:3];
  logic valid_q [0:3][0:3];
  logic signed [23:0] accum_q [0:3];
  logic busy_q;
  logic [3:0] cycle_q;

  assign ready_o = !busy_q;

  for (genvar r = 0; r < 4; r++) begin : row
    for (genvar c = 0; c < 4; c++) begin : pe
      wire valid_in;
      wire signed [7:0] activation_in;
      wire signed [23:0] partial_in;
      wire signed [7:0] gated_activation;
      wire signed [7:0] gated_weight;
      wire signed [15:0] product;
      if (r == 0) begin
        assign valid_in = busy_q && (cycle_q == c);
        assign activation_in = activations_q[c];
      end else begin
        assign valid_in = valid_q[r-1][c];
        assign activation_in = a_pipe[r-1][c];
      end
      if (c == 0)
        assign partial_in = 24'sd0;
      else
        assign partial_in = partial_q[r][c-1];

      assign gated_activation = (valid_in && activation_in != 0) ? activation_in : 8'sd0;
      assign gated_weight = (valid_in && activation_in != 0) ? weights_q[r][c] : 8'sd0;
      assign product = gated_activation * gated_weight;

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          weights_q[r][c] <= '0;
          a_pipe[r][c] <= '0;
          partial_q[r][c] <= '0;
          valid_q[r][c] <= 1'b0;
        end else begin
          if (load_weights_i && ready_o)
            weights_q[r][c] <= weights_i[(r*4+c)*8 +: 8];
          if (clear_i) begin
            a_pipe[r][c] <= '0;
            partial_q[r][c] <= '0;
            valid_q[r][c] <= 1'b0;
          end else begin
            valid_q[r][c] <= valid_in;
            if (valid_in) begin
              a_pipe[r][c] <= activation_in;
              partial_q[r][c] <= partial_in + {{8{product[15]}}, product};
            end
          end
        end
      end
    end
    assign accumulations_o[r*24 +: 24] = accum_q[r];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy_q <= 1'b0;
      cycle_q <= '0;
      out_valid_o <= 1'b0;
      for (int r = 0; r < 4; r++) begin
        accum_q[r] <= '0;
        activations_q[r] <= '0;
      end
    end else begin
      out_valid_o <= 1'b0;
      if (clear_i) begin
        busy_q <= 1'b0;
        cycle_q <= '0;
        for (int r = 0; r < 4; r++)
          accum_q[r] <= '0;
      end else begin
        if (in_valid_i && ready_o) begin
          for (int c = 0; c < 4; c++)
            activations_q[c] <= activations_i[c*8 +: 8];
          busy_q <= 1'b1;
          cycle_q <= '0;
        end else if (busy_q) begin
          cycle_q <= cycle_q + 1'b1;
          if (cycle_q == 4'd7) begin
            busy_q <= 1'b0;
            out_valid_o <= 1'b1;
          end
        end
        for (int r = 0; r < 4; r++)
          if (valid_q[r][3])
            accum_q[r] <= accum_q[r] + partial_q[r][3];
      end
    end
  end
endmodule
