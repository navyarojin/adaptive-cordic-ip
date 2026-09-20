






interface act_if
  import cordic_pkg::*;
(input logic clk, input logic rst_n);

  
  logic                            x_valid_i;
  logic signed [INPUT_WIDTH-1:0]   x_i;
  logic                            round_mode_en_i;
  logic ready_i;
  logic request_ack_i, request_error_i;
  logic [ITER_CNT_WIDTH-1:0] dbg_full_iter;

  
  logic                            result_valid_o;
  logic signed [OUTPUT_WIDTH-1:0]  result_o;
  logic                            irq_o;

  
  logic                       dbg_enable_o;
  logic [1:0]                 dbg_activation_mode_o;
  logic [15:0]                dbg_error_threshold_o;
  logic [ITER_CNT_WIDTH-1:0]  dbg_iter_budget_o;
  logic                       dbg_core_start_o;
  logic                       dbg_sample_mode_o;
  logic                       dbg_core_valid_o;
  logic                       dbg_overflow_o;
  logic [RESIDUAL_WIDTH-1:0]  dbg_residual_o;

  clocking drv_cb @(posedge clk);
    output x_valid_i, x_i, round_mode_en_i;
    input  result_valid_o, result_o, ready_i, request_ack_i, request_error_i;
  endclocking

  clocking mon_cb @(posedge clk);
    input x_valid_i, x_i, result_valid_o, result_o, irq_o, dbg_full_iter,
          dbg_enable_o, dbg_activation_mode_o, dbg_error_threshold_o,
          dbg_iter_budget_o, dbg_core_start_o, dbg_sample_mode_o,
          dbg_core_valid_o, dbg_overflow_o, dbg_residual_o;
  endclocking

  modport DRIVER (clocking drv_cb, input clk, rst_n);
  modport MONITOR(clocking mon_cb, input clk, rst_n);

endinterface : act_if
