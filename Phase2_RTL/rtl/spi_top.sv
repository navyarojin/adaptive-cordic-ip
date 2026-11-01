`timescale 1ns/1ps

module npu_spi_top #(parameter int ACTIVATION_LANES = 1) (
  input logic clk, rst_n,
  input logic spi_cs_n_i, spi_sck_i, spi_mosi_i,
  output logic spi_miso_o, spi_miso_oe_o, irq_o
);
  (* ASYNC_REG = "TRUE" *) logic [1:0] reset_release_q;
  wire reset_n = reset_release_q[1];
  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) reset_release_q <= 0;
    else reset_release_q <= {reset_release_q[0], 1'b1};

  logic PSEL, PENABLE, PWRITE, PREADY, PSLVERR;
  logic [31:0] PADDR, PWDATA, PRDATA;
  logic req, wen, gnt, rvalid, error;
  logic [31:0] addr, wdata, rdata;
  logic [3:0] be;
  npu_spi_bridge u_spi (
    .clk, .rst_n(reset_n), .spi_cs_n_i, .spi_sck_i, .spi_mosi_i, .spi_miso_o, .spi_miso_oe_o,
    .PSEL, .PENABLE, .PWRITE, .PADDR, .PWDATA, .PRDATA, .PREADY, .PSLVERR,
    .tcdm_req_o(req), .tcdm_wen_o(wen), .tcdm_addr_o(addr), .tcdm_wdata_o(wdata),
    .tcdm_be_o(be), .tcdm_gnt_i(gnt), .tcdm_rvalid_i(rvalid), .tcdm_error_i(error), .tcdm_rdata_i(rdata)
  );
  accelerator_top #(.ACTIVATION_LANES(ACTIVATION_LANES)) u_accelerator (
    .clk, .rst_n(reset_n), .PSEL, .PENABLE, .PWRITE, .PADDR, .PWDATA, .PRDATA, .PREADY, .PSLVERR,
    .tcdm_req_i(req), .tcdm_wen_i(wen), .tcdm_addr_i(addr), .tcdm_wdata_i(wdata),
    .tcdm_be_i(be), .tcdm_gnt_o(gnt), .tcdm_rvalid_o(rvalid), .tcdm_error_o(error),
    .tcdm_rdata_o(rdata), .irq_o,
    .dbg_enable_o(), .dbg_activation_mode_o(), .dbg_error_threshold_o(),
    .dbg_iter_budget_o(), .dbg_core_start_o(), .dbg_sample_mode_o(),
    .dbg_core_valid_o(), .dbg_overflow_o(), .dbg_residual_o(),
    .dbg_result_valid_o(), .dbg_result_o()
  );
endmodule
