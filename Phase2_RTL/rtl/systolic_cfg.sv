module zero_aware_systolic_npu_param #(
  parameter int ARRAY_DIM = 4,
  parameter int DATA_WIDTH = 8,
  parameter int ACC_WIDTH = 24
) (
  input logic clk, rst_n, clear_i, load_weights_i,
  input logic signed [ARRAY_DIM*ARRAY_DIM*DATA_WIDTH-1:0] weights_i,
  input logic in_valid_i,
  input logic signed [ARRAY_DIM*DATA_WIDTH-1:0] activations_i,
  output logic ready_o, out_valid_o,
  output logic signed [ARRAY_DIM*ACC_WIDTH-1:0] accumulations_o
);
  localparam int CYCLE_WIDTH = (ARRAY_DIM < 2) ? 1 : $clog2(2*ARRAY_DIM+1);
  logic signed [DATA_WIDTH-1:0] weights_q [0:ARRAY_DIM-1][0:ARRAY_DIM-1];
  logic signed [DATA_WIDTH-1:0] activations_q [0:ARRAY_DIM-1];
  logic signed [DATA_WIDTH-1:0] a_pipe [0:ARRAY_DIM-1][0:ARRAY_DIM-1];
  logic signed [ACC_WIDTH-1:0] partial_q [0:ARRAY_DIM-1][0:ARRAY_DIM-1];
  logic valid_q [0:ARRAY_DIM-1][0:ARRAY_DIM-1];
  logic signed [ACC_WIDTH-1:0] accum_q [0:ARRAY_DIM-1];
  logic busy_q;
  logic [CYCLE_WIDTH-1:0] cycle_q;
  initial if (ARRAY_DIM != 4 && ARRAY_DIM != 8 && ARRAY_DIM != 16) $fatal(1, "ARRAY_DIM must be 4, 8, or 16");
  initial if (DATA_WIDTH < 2 || ACC_WIDTH < 2*DATA_WIDTH) $fatal(1, "Invalid MAC widths");
  assign ready_o = !busy_q;
  for (genvar r=0; r<ARRAY_DIM; r++) begin : row
    for (genvar c=0; c<ARRAY_DIM; c++) begin : pe
      wire valid_in;
      wire signed [DATA_WIDTH-1:0] activation_in;
      wire signed [ACC_WIDTH-1:0] partial_in;
      if (r == 0) begin : first_row
        assign valid_in = busy_q && cycle_q == c;
        assign activation_in = activations_q[c];
      end else begin : following_row
        assign valid_in = valid_q[r-1][c];
        assign activation_in = a_pipe[r-1][c];
      end
      if (c == 0) begin : first_column
        assign partial_in = '0;
      end else begin : following_column
        assign partial_in = partial_q[r][c-1];
      end
      wire signed [DATA_WIDTH-1:0] gated_activation = (valid_in && activation_in != 0) ? activation_in : '0;
      wire signed [DATA_WIDTH-1:0] gated_weight = (valid_in && activation_in != 0) ? weights_q[r][c] : '0;
      wire signed [2*DATA_WIDTH-1:0] product = gated_activation * gated_weight;
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin weights_q[r][c]<='0; a_pipe[r][c]<='0; partial_q[r][c]<='0; valid_q[r][c]<=0; end
        else begin
          if (load_weights_i && ready_o) weights_q[r][c] <= weights_i[(r*ARRAY_DIM+c)*DATA_WIDTH +: DATA_WIDTH];
          if (clear_i) begin a_pipe[r][c]<='0; partial_q[r][c]<='0; valid_q[r][c]<=0; end
          else begin valid_q[r][c] <= valid_in; if (valid_in) begin a_pipe[r][c]<=activation_in; partial_q[r][c] <= partial_in + {{(ACC_WIDTH-2*DATA_WIDTH){product[2*DATA_WIDTH-1]}},product}; end end
        end
      end
    end
    assign accumulations_o[r*ACC_WIDTH +: ACC_WIDTH] = accum_q[r];
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin busy_q<=0; cycle_q<='0; out_valid_o<=0; for (int r=0;r<ARRAY_DIM;r++) begin accum_q[r]<='0; activations_q[r]<='0; end end
    else begin
      out_valid_o<=0;
      if (clear_i) begin busy_q<=0; cycle_q<='0; for (int r=0;r<ARRAY_DIM;r++) accum_q[r]<='0; end
      else begin
        if (in_valid_i && ready_o) begin for (int c=0;c<ARRAY_DIM;c++) activations_q[c]<=activations_i[c*DATA_WIDTH +: DATA_WIDTH]; busy_q<=1; cycle_q<='0; end
        else if (busy_q) begin cycle_q<=cycle_q+1'b1; if (cycle_q == 2*ARRAY_DIM-1) begin busy_q<=0; out_valid_o<=1; end end
        for (int r=0;r<ARRAY_DIM;r++) if (valid_q[r][ARRAY_DIM-1]) accum_q[r]<=accum_q[r]+partial_q[r][ARRAY_DIM-1];
      end
    end
  end
endmodule
