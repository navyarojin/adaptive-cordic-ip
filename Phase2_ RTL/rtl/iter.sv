import cordic_pkg::*;

module iteration_lut (
  input  logic clk,
  input  logic rst_n,
  input  logic lut_reset_i,
  input  logic lut_freeze_i,
  input  logic [$clog2(NUM_MAG_BINS)-1:0] read_bin_i,
  output logic [ITER_CNT_WIDTH-1:0] budget_o,
  input  logic update_valid_i,
  input  logic [$clog2(NUM_MAG_BINS)-1:0] update_bin_i,
  input  logic increase_i,
  input  logic decrease_i,
  input  logic force_full_i,
  input  logic [ITER_CNT_WIDTH-1:0] min_iter_i,
  input  logic [ITER_CNT_WIDTH-1:0] max_iter_i,
  input  logic [ITER_CNT_WIDTH-1:0] full_iter_i
);

  logic [ITER_CNT_WIDTH-1:0] budget_q [0:NUM_MAG_BINS-1];
  integer i;

  always_comb begin
    budget_o = budget_q[read_bin_i];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < NUM_MAG_BINS; i = i + 1)
        budget_q[i] <= ITER_CNT_WIDTH'(MAG_BIN_SEED_BUDGET[i]);
    end else if (lut_reset_i) begin
      for (i = 0; i < NUM_MAG_BINS; i = i + 1)
        budget_q[i] <= ITER_CNT_WIDTH'(MAG_BIN_SEED_BUDGET[i]);
    end else if (update_valid_i && !lut_freeze_i) begin
      if (force_full_i)
        budget_q[update_bin_i] <= full_iter_i;
      else if (increase_i && (budget_q[update_bin_i] < max_iter_i))
        budget_q[update_bin_i] <= budget_q[update_bin_i] + 1'b1;
      else if (decrease_i && (budget_q[update_bin_i] > min_iter_i))
        budget_q[update_bin_i] <= budget_q[update_bin_i] - 1'b1;
    end
  end

endmodule : iteration_lut
