




`timescale 1ns/1ps

module hdl_top;
  import cordic_pkg::*;

  logic clk;
  logic rst_n;
  logic boot_rst_n;
  assign rst_n = boot_rst_n && !u_tcdm_if.reset_request;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  initial begin
    boot_rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk);
    boot_rst_n = 1'b1;
  end

  initial begin
    if ($test$plusargs("DUMP_VCD")) begin
      $dumpfile("activation_ip_uvm.vcd");
      $dumpvars(0, hdl_top);
    end
  end

  apb_if u_apb_if (.clk(clk), .rst_n(rst_n));
  act_if u_act_if (.clk(clk), .rst_n(rst_n));
  tcdm_if u_tcdm_if (.clk(clk), .rst_n(rst_n));

  assign u_act_if.ready_i = !u_dut.busy && u_dut.act_ready;
  assign u_act_if.request_ack_i = u_tcdm_if.rvalid && !u_tcdm_if.active;
  assign u_act_if.request_error_i = u_tcdm_if.error;
  assign u_act_if.dbg_full_iter = bounded_full_iter(u_dut.u_activation.csr2ctrl.full_iter,
                                                   u_dut.u_activation.csr2ctrl.min_iter);
  assign u_tcdm_if.irq = u_act_if.irq_o;
  assign u_tcdm_if.core_start = u_act_if.dbg_core_start_o;
  assign u_tcdm_if.sample_mode = u_act_if.dbg_sample_mode_o;
  assign u_tcdm_if.budget = u_act_if.dbg_iter_budget_o;

  accelerator_top u_dut (
    .clk                    (clk),
    .rst_n                  (rst_n),

    .PSEL                   (u_apb_if.PSEL),
    .PENABLE                (u_apb_if.PENABLE),
    .PWRITE                 (u_apb_if.PWRITE),
    .PADDR                  (u_apb_if.PADDR),
    .PWDATA                 (u_apb_if.PWDATA),
    .PRDATA                 (u_apb_if.PRDATA),
    .PREADY                 (u_apb_if.PREADY),
    .PSLVERR                (u_apb_if.PSLVERR),

    .tcdm_req_i             (u_tcdm_if.active ? u_tcdm_if.req : u_act_if.x_valid_i),
    .tcdm_wen_i             (u_tcdm_if.active ? u_tcdm_if.wen : 1'b0),
    .tcdm_addr_i            (u_tcdm_if.active ? u_tcdm_if.addr : 32'h200),
    .tcdm_wdata_i           (u_tcdm_if.active ? u_tcdm_if.wdata : {{13{u_act_if.x_i[18]}},u_act_if.x_i}),
    .tcdm_be_i              (u_tcdm_if.active ? u_tcdm_if.be : 4'hf),
    .tcdm_gnt_o             (u_tcdm_if.gnt),
    .tcdm_rvalid_o          (u_tcdm_if.rvalid),
    .tcdm_rdata_o           (u_tcdm_if.rdata),
    .tcdm_error_o           (u_tcdm_if.error),
    .dbg_result_valid_o     (u_act_if.result_valid_o),
    .dbg_result_o           (u_act_if.result_o),
    .irq_o                  (u_act_if.irq_o),

    .dbg_enable_o           (u_act_if.dbg_enable_o),
    .dbg_activation_mode_o  (u_act_if.dbg_activation_mode_o),
    .dbg_error_threshold_o  (u_act_if.dbg_error_threshold_o),
    .dbg_iter_budget_o      (u_act_if.dbg_iter_budget_o),
    .dbg_core_start_o       (u_act_if.dbg_core_start_o),
    .dbg_sample_mode_o      (u_act_if.dbg_sample_mode_o),
    .dbg_core_valid_o       (u_act_if.dbg_core_valid_o),
    .dbg_overflow_o         (u_act_if.dbg_overflow_o),
    .dbg_residual_o         (u_act_if.dbg_residual_o)
  );

endmodule : hdl_top
