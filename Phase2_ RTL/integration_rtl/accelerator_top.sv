module accelerator_top
  import cordic_pkg::*;
(
  input logic clk, rst_n,
  input logic PSEL, PENABLE, PWRITE,
  input logic [31:0] PADDR, PWDATA,
  output logic [31:0] PRDATA,
  output logic PREADY, PSLVERR,
  input logic tcdm_req_i, tcdm_wen_i,
  input logic [31:0] tcdm_addr_i, tcdm_wdata_i,
  input logic [3:0] tcdm_be_i,
  output logic tcdm_gnt_o, tcdm_rvalid_o, tcdm_error_o,
  output logic [31:0] tcdm_rdata_o,
  output logic irq_o,
  output logic dbg_enable_o,
  output logic [1:0] dbg_activation_mode_o,
  output logic [15:0] dbg_error_threshold_o,
  output logic [ITER_CNT_WIDTH-1:0] dbg_iter_budget_o,
  output logic dbg_core_start_o, dbg_sample_mode_o,
  output logic dbg_core_valid_o, dbg_overflow_o,
  output logic [RESIDUAL_WIDTH-1:0] dbg_residual_o,
  output logic dbg_result_valid_o,
  output logic signed [OUTPUT_WIDTH-1:0] dbg_result_o
);
  typedef enum logic [3:0] {IDLE, N_CLEAR, N_LOAD, N_START, N_WAIT,
    A_ISSUE, A_WAIT, DIRECT_ISSUE, DIRECT_WAIT} state_t;
  state_t state_q;
  logic [127:0] weights_q;
  logic [31:0] activations_q;
  logic [95:0] raw_q, npu_result;
  logic signed [15:0] results_q [0:3];
  logic [1:0] lane_q;
  logic [4:0] shift_q;
  logic done_q, done_irq_enable_q;
  logic npu_ready, npu_valid, act_ready, act_irq;
  logic act_start;
  logic signed [18:0] act_x, direct_q;
  logic signed [15:0] direct_result_q;
  logic [31:0] apb_rdata;
  logic apb_ready, apb_error;
  logic busy;

  function automatic logic signed [18:0] quantize(input logic signed [23:0] value);
    logic signed [23:0] shifted;
    shifted = value >>> shift_q;
    if (shifted > 24'sd262143) return 19'sd262143;
    if (shifted < -24'sd262144) return -19'sd262144;
    return shifted[18:0];
  endfunction

  assign busy = (state_q != IDLE);
  assign tcdm_gnt_o = tcdm_req_i;
  assign PRDATA = apb_rdata;
  assign PREADY = busy ? 1'b1 : apb_ready;
  assign PSLVERR = (busy && PSEL && PENABLE) || apb_error;
  assign irq_o = act_irq || (done_q && done_irq_enable_q);
  assign act_start = act_ready && (state_q == A_ISSUE || state_q == DIRECT_ISSUE);
  assign act_x = (state_q == DIRECT_ISSUE) ? direct_q : quantize($signed(raw_q[lane_q*24 +: 24]));

  zero_aware_systolic_npu u_npu (
    .clk(clk), .rst_n(rst_n), .clear_i(state_q == N_CLEAR),
    .load_weights_i(state_q == N_LOAD), .weights_i(weights_q),
    .in_valid_i(state_q == N_START), .activations_i(activations_q),
    .ready_o(npu_ready), .out_valid_o(npu_valid), .accumulations_o(npu_result)
  );

  activation_ip_top u_activation (
    .clk(clk), .rst_n(rst_n), .PSEL(PSEL && !busy), .PENABLE(PENABLE),
    .PWRITE(PWRITE), .PADDR(PADDR), .PWDATA(PWDATA),
    .PRDATA(apb_rdata), .PREADY(apb_ready), .PSLVERR(apb_error),
    .x_valid_i(act_start), .x_i(act_x), .result_valid_o(dbg_result_valid_o),
    .result_o(dbg_result_o), .round_mode_en_i(1'b1), .irq_o(act_irq),
    .ready_o(act_ready), .dbg_enable_o(dbg_enable_o),
    .dbg_activation_mode_o(dbg_activation_mode_o),
    .dbg_error_threshold_o(dbg_error_threshold_o), .dbg_iter_budget_o(dbg_iter_budget_o),
    .dbg_core_start_o(dbg_core_start_o), .dbg_sample_mode_o(dbg_sample_mode_o),
    .dbg_core_valid_o(dbg_core_valid_o), .dbg_overflow_o(dbg_overflow_o),
    .dbg_residual_o(dbg_residual_o)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= IDLE;
      weights_q <= '0;
      activations_q <= '0;
      raw_q <= '0;
      lane_q <= '0;
      shift_q <= '0;
      done_q <= 1'b0;
      done_irq_enable_q <= 1'b0;
      direct_q <= '0;
      direct_result_q <= '0;
      tcdm_rvalid_o <= 1'b0;
      tcdm_rdata_o <= '0;
      tcdm_error_o <= 1'b0;
      for (int i = 0; i < 4; i++) results_q[i] <= '0;
    end else begin
      tcdm_rvalid_o <= tcdm_req_i && tcdm_gnt_o;
      tcdm_rdata_o <= '0;
      tcdm_error_o <= 1'b0;
      case (state_q)
        N_CLEAR: state_q <= N_LOAD;
        N_LOAD: state_q <= N_START;
        N_START: if (npu_ready) state_q <= N_WAIT;
        N_WAIT: if (npu_valid) begin
          raw_q <= npu_result;
          lane_q <= '0;
          state_q <= A_ISSUE;
        end
        A_ISSUE: if (act_ready) state_q <= A_WAIT;
        A_WAIT: if (dbg_result_valid_o) begin
          results_q[lane_q] <= dbg_result_o;
          if (lane_q == 3) begin
            done_q <= 1'b1;
            state_q <= IDLE;
          end else begin
            lane_q <= lane_q + 1'b1;
            state_q <= A_ISSUE;
          end
        end
        DIRECT_ISSUE: if (act_ready) state_q <= DIRECT_WAIT;
        DIRECT_WAIT: if (dbg_result_valid_o) begin
          direct_result_q <= dbg_result_o;
          state_q <= IDLE;
        end
        default: ;
      endcase
      if (tcdm_req_i && tcdm_gnt_o) begin
        if (tcdm_addr_i[1:0] != 0) begin
          tcdm_error_o <= 1'b1;
        end else if (!tcdm_wen_i) begin
          if (busy) begin
            tcdm_error_o <= 1'b1;
          end else if (tcdm_addr_i < 32'h40) begin
            if (tcdm_be_i[0]) weights_q[tcdm_addr_i[5:2]*8 +: 8] <= tcdm_wdata_i[7:0];
          end else if (tcdm_addr_i >= 32'h40 && tcdm_addr_i < 32'h50) begin
            if (tcdm_be_i[0]) activations_q[tcdm_addr_i[3:2]*8 +: 8] <= tcdm_wdata_i[7:0];
          end else case (tcdm_addr_i)
            32'h100: if (tcdm_be_i[0]) begin
              if (tcdm_wdata_i[1]) done_q <= 1'b0;
              if (tcdm_wdata_i[0]) begin
                if (act_ready) begin
                  done_q <= 1'b0;
                  state_q <= N_CLEAR;
                end else tcdm_error_o <= 1'b1;
              end
            end
            32'h104: if (tcdm_be_i[0]) shift_q <= tcdm_wdata_i[4:0];
            32'h108: if (tcdm_be_i[0]) done_irq_enable_q <= tcdm_wdata_i[0];
            32'h200: begin
              if (act_ready && &tcdm_be_i) begin
                direct_q <= tcdm_wdata_i[18:0];
                state_q <= DIRECT_ISSUE;
              end else tcdm_error_o <= 1'b1;
            end
            default: tcdm_error_o <= 1'b1;
          endcase
        end else begin
          if (tcdm_addr_i < 32'h40)
            tcdm_rdata_o <= {24'b0, weights_q[tcdm_addr_i[5:2]*8 +: 8]};
          else if (tcdm_addr_i >= 32'h40 && tcdm_addr_i < 32'h50)
            tcdm_rdata_o <= {24'b0, activations_q[tcdm_addr_i[3:2]*8 +: 8]};
          else if (tcdm_addr_i >= 32'h80 && tcdm_addr_i < 32'h90)
            tcdm_rdata_o <= {{16{results_q[tcdm_addr_i[3:2]][15]}}, results_q[tcdm_addr_i[3:2]]};
          else if (tcdm_addr_i >= 32'h90 && tcdm_addr_i < 32'ha0)
            tcdm_rdata_o <= {{8{raw_q[tcdm_addr_i[3:2]*24+23]}}, raw_q[tcdm_addr_i[3:2]*24 +: 24]};
          else case (tcdm_addr_i)
            32'h100: tcdm_rdata_o <= {30'b0, done_q, busy};
            32'h104: tcdm_rdata_o <= {27'b0, shift_q};
            32'h108: tcdm_rdata_o <= {31'b0, done_irq_enable_q};
            32'h204: tcdm_rdata_o <= {{16{direct_result_q[15]}}, direct_result_q};
            default: tcdm_error_o <= 1'b1;
          endcase
        end
      end
    end
  end
endmodule
