`timescale 1ns/1ps

module tb_qualification_ctrl;
  import cordic_pkg::*;

  logic clk;
  logic rst_n;
  logic x_valid_i;
  logic signed [INPUT_WIDTH-1:0] x_i;
  ctrl_to_core_t core_ctrl_o;
  core_to_ctrl_t core_ctrl_i;
  csr_to_ctrl_t csr_i;
  ctrl_to_csr_t csr_o;
  logic result_valid_o;
  logic signed [OUTPUT_WIDTH-1:0] result_o;

  qualification_ctrl dut (
    .clk(clk), .rst_n(rst_n),
    .x_valid_i(x_valid_i), .x_i(x_i),
    .core_ctrl_o(core_ctrl_o), .core_ctrl_i(core_ctrl_i),
    .csr_i(csr_i), .csr_o(csr_o),
    .result_valid_o(result_valid_o), .result_o(result_o)
  );

  always #5 clk = ~clk;

  task automatic check_true(input logic condition, input string message);
    if (!condition)
      $fatal(1, "FAIL: %s", message);
  endtask

  task automatic send_request(input logic signed [INPUT_WIDTH-1:0] value,
                              input logic [ITER_CNT_WIDTH-1:0] expected_budget);
    @(negedge clk);
    x_i       <= value;
    x_valid_i <= 1'b1;
    #1;
    check_true(core_ctrl_o.start, "controller did not launch the core");
    check_true(core_ctrl_o.sample_mode, "request was not selected for qualification");
    check_true(core_ctrl_o.iter_budget == expected_budget, "unexpected LUT iteration budget");
    @(posedge clk);
    @(negedge clk);
    x_valid_i <= 1'b0;
  endtask

  task automatic complete_core(input logic signed [OUTPUT_WIDTH-1:0] early,
                               input logic signed [OUTPUT_WIDTH-1:0] full,
                               input logic [RESIDUAL_WIDTH-1:0] residual,
                               input logic overflow);
    @(negedge clk);
    core_ctrl_i              <= '0;
    core_ctrl_i.valid        <= 1'b1;
    core_ctrl_i.early_result <= early;
    core_ctrl_i.full_result  <= full;
    core_ctrl_i.residual     <= residual;
    core_ctrl_i.iter_used    <= core_ctrl_o.iter_budget;
    core_ctrl_i.overflow     <= overflow;
    @(posedge clk);
    #1;
    check_true(result_valid_o, "controller did not return a result");
    @(negedge clk);
    core_ctrl_i.valid <= 1'b0;
  endtask

  initial begin
    clk          = 1'b0;
    rst_n        = 1'b0;
    x_valid_i    = 1'b0;
    x_i          = '0;
    core_ctrl_i  = '0;
    csr_i        = '0;

    csr_i.enable              = 1'b1;
    csr_i.error_threshold     = 16'd1;
    csr_i.sample_rate         = 8'd1;
    csr_i.min_iter            = 8'd6;
    csr_i.max_iter            = 8'd14;
    csr_i.full_iter           = 8'd14;
    csr_i.qualification_count = 16'd2;
    csr_i.violation_limit     = 16'd2;
    csr_i.update_interval     = 16'd0;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    check_true(csr_o.ready_flag, "controller is not ready after reset");

    send_request(19'sd0, 8'd14);
    complete_core(16'sd100, 16'sd101, 18'd1, 1'b0);
    check_true(result_o == 16'sd100, "in-tolerance sample must return early result");
    check_true(csr_o.sample_count == 32'd1, "sample count after first sample");

    send_request(19'sd0, 8'd14);
    complete_core(16'sd102, 16'sd103, 18'd1, 1'b0);
    check_true(result_o == 16'sd102, "second in-tolerance sample returned wrong result");

    send_request(19'sd0, 8'd13);
    complete_core(16'sd200, 16'sd204, 18'd4, 1'b0);
    check_true(result_o == 16'sd204, "violating sample must return full result");
    check_true(csr_o.fallback_count == 32'd1, "fallback count was not incremented");
    check_true(csr_o.fallback_flag, "fallback status was not latched");

    send_request(19'sd0, 8'd14);
    complete_core(16'sd10, 16'sd10, 18'd0, 1'b1);
    check_true(csr_o.fault_flag, "overflow must latch the fault status");

    csr_i.enable = 1'b0;
    @(negedge clk);
    x_i       <= 19'sd0;
    x_valid_i <= 1'b1;
    #1;
    check_true(!core_ctrl_o.start, "disabled controller launched the core");
    @(negedge clk);
    x_valid_i <= 1'b0;

    $display("PASS: qualification_ctrl directed tests completed");
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "FAIL: timeout");
  end
endmodule : tb_qualification_ctrl
