import cordic_pkg::*;

module qualification_ctrl (
  input  logic clk,
  input  logic rst_n,

  input  logic                          x_valid_i,
  input  logic signed [INPUT_WIDTH-1:0] x_i,
  output ctrl_to_core_t core_ctrl_o,
  input  core_to_ctrl_t core_ctrl_i,
  input  csr_to_ctrl_t  csr_i,
  output ctrl_to_csr_t  csr_o,
  output logic                             result_valid_o,
  output logic signed [OUTPUT_WIDTH-1:0]   result_o
);

  typedef enum logic {ST_IDLE, ST_WAIT_CORE} state_t;
  state_t state_q;

  localparam logic [15:0] COUNT_MAX = 16'hffff;
  localparam logic [ITER_CNT_WIDTH-1:0] ITER_MAX = ITER_CNT_WIDTH'(MAX_ITER);
  localparam logic [1:0] MODE_TANH    = 2'b00;
  localparam logic [1:0] MODE_SIGMOID = 2'b01;
  localparam logic [1:0] MODE_RELU    = 2'b10;
  localparam logic [1:0] MODE_LINEAR  = 2'b11;

  logic [15:0] success_count_q [0:NUM_MAG_BINS-1];
  logic [15:0] violation_count_q [0:NUM_MAG_BINS-1];
  logic forced_full_q [0:NUM_MAG_BINS-1];

  logic [31:0] sample_count_q;
  logic [15:0] max_error_q;
  logic [31:0] fallback_count_q;
  logic        fault_flag_q;
  logic        fallback_flag_q;

  logic [7:0] sample_phase_q;
  logic [15:0] update_age_q;

  logic [$clog2(NUM_MAG_BINS)-1:0] active_bin_q;
  logic active_sample_q;

  logic [INPUT_WIDTH-1:0] x_magnitude;
  logic [$clog2(NUM_MAG_BINS)-1:0] x_bin;
  logic [$clog2(NUM_MAG_BINS)-1:0] lut_read_bin;
  logic [ITER_CNT_WIDTH-1:0] cfg_min_iter;
  logic [ITER_CNT_WIDTH-1:0] cfg_max_iter;
  logic [ITER_CNT_WIDTH-1:0] cfg_full_iter;
  logic [ITER_CNT_WIDTH-1:0] selected_iter;
  logic [ITER_CNT_WIDTH-1:0] lut_budget;
  logic sample_this_request;
  logic update_allowed;
  logic violation_event;
  logic success_reduce_event;
  logic lut_write_this_result;
  logic lut_force_full;
  logic lut_increase;
  logic lut_decrease;
  integer i;

  function automatic logic [$clog2(NUM_MAG_BINS)-1:0] magnitude_bin(
    input logic [INPUT_WIDTH-1:0] magnitude
  );
    integer edge_idx;
    begin
      magnitude_bin = NUM_MAG_BINS - 1;
      for (edge_idx = 0; edge_idx < NUM_MAG_EDGES; edge_idx = edge_idx + 1) begin
        if ((magnitude < MAG_BIN_EDGES[edge_idx]) && (magnitude_bin == NUM_MAG_BINS - 1))
          magnitude_bin = edge_idx;
      end
    end
  endfunction

  function automatic logic signed [OUTPUT_WIDTH-1:0] bypass_result(
    input logic signed [INPUT_WIDTH-1:0] value,
    input logic [1:0] mode
  );
    begin
      if (mode == MODE_RELU) begin
        if (value <= 0)
          bypass_result = '0;
        else if (value > 19'sd32767)
          bypass_result = 16'sd32767;
        else
          bypass_result = value[OUTPUT_WIDTH-1:0];
      end else begin
        if (value > 19'sd32767)
          bypass_result = 16'sd32767;
        else if (value < -19'sd32768)
          bypass_result = -16'sd32768;
        else
          bypass_result = value[OUTPUT_WIDTH-1:0];
      end
    end
  endfunction

  assign x_magnitude = x_i[INPUT_WIDTH-1] ? (~x_i + 1'b1) : x_i;
  assign x_bin = magnitude_bin(x_magnitude);
  assign lut_read_bin = (state_q == ST_IDLE) ? x_bin : active_bin_q;

  always_comb begin
    if (csr_i.min_iter < MIN_ITER_FLOOR)
      cfg_min_iter = ITER_CNT_WIDTH'(MIN_ITER_FLOOR);
    else if (csr_i.min_iter > ITER_MAX)
      cfg_min_iter = ITER_MAX;
    else
      cfg_min_iter = csr_i.min_iter[ITER_CNT_WIDTH-1:0];

    if (csr_i.max_iter < cfg_min_iter)
      cfg_max_iter = cfg_min_iter;
    else if (csr_i.max_iter > ITER_MAX)
      cfg_max_iter = ITER_MAX;
    else
      cfg_max_iter = csr_i.max_iter[ITER_CNT_WIDTH-1:0];

    if (csr_i.full_iter < cfg_min_iter)
      cfg_full_iter = cfg_min_iter;
    else if (csr_i.full_iter > ITER_MAX)
      cfg_full_iter = ITER_MAX;
    else
      cfg_full_iter = csr_i.full_iter[ITER_CNT_WIDTH-1:0];

    selected_iter = lut_budget;
    if (selected_iter < cfg_min_iter)
      selected_iter = cfg_min_iter;
    if (selected_iter > cfg_max_iter)
      selected_iter = cfg_max_iter;
    if (selected_iter > cfg_full_iter)
      selected_iter = cfg_full_iter;
    if (forced_full_q[lut_read_bin])
      selected_iter = cfg_full_iter;

    sample_this_request = (csr_i.sample_rate == 8'd0)
                        ? (sample_phase_q == 8'hff)
                        : (sample_phase_q == (csr_i.sample_rate - 1'b1));
    update_allowed = (csr_i.update_interval == 16'd0) ||
                     (update_age_q >= csr_i.update_interval);

    violation_event = active_sample_q &&
                      (core_ctrl_i.residual > csr_i.error_threshold);
    success_reduce_event = active_sample_q && !violation_event &&
                           (lut_budget > cfg_min_iter) &&
                           ((csr_i.qualification_count == 16'd0) ||
                            (success_count_q[active_bin_q] + 1'b1 >=
                             csr_i.qualification_count));
    lut_write_this_result = (state_q == ST_WAIT_CORE) && core_ctrl_i.valid &&
                            !csr_i.lut_freeze &&
                            (violation_event ||
                             (update_allowed && success_reduce_event));
    lut_force_full = violation_event && (csr_i.violation_limit != 16'd0) &&
                     (violation_count_q[active_bin_q] + 1'b1 >= csr_i.violation_limit);
    lut_increase = violation_event && !lut_force_full;
    lut_decrease = !violation_event && success_reduce_event;
  end

  iteration_lut u_iteration_lut (
    .clk(clk),
    .rst_n(rst_n),
    .lut_reset_i(csr_i.lut_reset),
    .lut_freeze_i(csr_i.lut_freeze),
    .read_bin_i(lut_read_bin),
    .budget_o(lut_budget),
    .update_valid_i(lut_write_this_result),
    .update_bin_i(active_bin_q),
    .increase_i(lut_increase),
    .decrease_i(lut_decrease),
    .force_full_i(lut_force_full),
    .min_iter_i(cfg_min_iter),
    .max_iter_i(cfg_max_iter),
    .full_iter_i(cfg_full_iter)
  );

  always_comb begin
    core_ctrl_o = '0;
    if ((state_q == ST_IDLE) && x_valid_i && csr_i.enable &&
        ((csr_i.activation_mode == MODE_TANH) ||
         (csr_i.activation_mode == MODE_SIGMOID))) begin
      core_ctrl_o.start       = 1'b1;
      core_ctrl_o.x_in        = x_i;
      core_ctrl_o.iter_budget = selected_iter;
      core_ctrl_o.sample_mode = sample_this_request;
      core_ctrl_o.sigmoid_mode = (csr_i.activation_mode == MODE_SIGMOID);
    end

    csr_o.sample_count   = sample_count_q;
    csr_o.max_error      = max_error_q;
    csr_o.fallback_count = fallback_count_q;
    csr_o.fault_flag     = fault_flag_q;
    csr_o.fallback_flag  = fallback_flag_q;
    csr_o.ready_flag     = (state_q == ST_IDLE) && csr_i.enable;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q          <= ST_IDLE;
      sample_count_q   <= '0;
      max_error_q      <= '0;
      fallback_count_q <= '0;
      fault_flag_q     <= 1'b0;
      fallback_flag_q  <= 1'b0;
      sample_phase_q   <= '0;
      update_age_q     <= COUNT_MAX;
      active_bin_q     <= '0;
      active_sample_q  <= 1'b0;
      result_valid_o   <= 1'b0;
      result_o         <= '0;
      for (i = 0; i < NUM_MAG_BINS; i = i + 1) begin
        success_count_q[i]   <= '0;
        violation_count_q[i] <= '0;
        forced_full_q[i] <= 1'b0;
      end
    end else begin
      result_valid_o <= 1'b0;

      if (csr_i.lut_reset) begin
        sample_phase_q <= '0;
        fault_flag_q <= 1'b0;
        update_age_q <= COUNT_MAX;
        fallback_flag_q <= 1'b0;
        for (i = 0; i < NUM_MAG_BINS; i = i + 1) begin
          success_count_q[i]   <= '0;
          violation_count_q[i] <= '0;
          forced_full_q[i] <= 1'b0;
        end
      end else case (state_q)
        ST_IDLE: begin
          if (x_valid_i && csr_i.enable) begin
            if ((csr_i.activation_mode == MODE_RELU) ||
                (csr_i.activation_mode == MODE_LINEAR)) begin
              result_valid_o <= 1'b1;
              result_o <= bypass_result(x_i, csr_i.activation_mode);
            end else begin
              state_q         <= ST_WAIT_CORE;
              active_bin_q    <= x_bin;
              active_sample_q <= sample_this_request;
              if (csr_i.sample_rate == 8'd0)
                sample_phase_q <= sample_phase_q + 1'b1;
              else if (sample_this_request)
                sample_phase_q <= '0;
              else
                sample_phase_q <= sample_phase_q + 1'b1;
            end
          end
        end

        ST_WAIT_CORE: begin
          if (core_ctrl_i.valid) begin
            state_q        <= ST_IDLE;
            result_valid_o <= 1'b1;

            if (violation_event)
              result_o <= core_ctrl_i.full_result[OUTPUT_WIDTH-1:0];
            else
              result_o <= core_ctrl_i.early_result[OUTPUT_WIDTH-1:0];

            if (core_ctrl_i.overflow)
              fault_flag_q <= 1'b1;

            if (active_sample_q) begin
              sample_count_q <= sample_count_q + 1'b1;
              if (core_ctrl_i.residual > max_error_q)
                max_error_q <= core_ctrl_i.residual[15:0];

              if (violation_event) begin
                if (lut_force_full)
                  forced_full_q[active_bin_q] <= 1'b1;
                fallback_flag_q  <= 1'b1;
                fallback_count_q <= fallback_count_q + 1'b1;
                success_count_q[active_bin_q] <= '0;
                if (violation_count_q[active_bin_q] != COUNT_MAX)
                  violation_count_q[active_bin_q] <= violation_count_q[active_bin_q] + 1'b1;

                if (lut_write_this_result) begin
                  update_age_q <= '0;
                end
              end else begin
                violation_count_q[active_bin_q] <= '0;
                if (csr_i.qualification_count == 16'd0) begin
                  if (lut_write_this_result) begin
                    update_age_q <= '0;
                  end
                  success_count_q[active_bin_q] <= '0;
                end else if (success_count_q[active_bin_q] + 1'b1 >= csr_i.qualification_count) begin
                  success_count_q[active_bin_q] <= '0;
                  if (lut_write_this_result) begin
                    update_age_q <= '0;
                  end
                end else if (success_count_q[active_bin_q] != COUNT_MAX) begin
                  success_count_q[active_bin_q] <= success_count_q[active_bin_q] + 1'b1;
                end
              end
            end

            if (!lut_write_this_result && (update_age_q != COUNT_MAX))
              update_age_q <= update_age_q + 1'b1;
          end
        end

        default: state_q <= ST_IDLE;
      endcase
    end
  end

endmodule : qualification_ctrl
