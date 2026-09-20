import cordic_pkg::*;

module cordic_activation_top (
  input  logic clk,
  input  logic rst_n,

  input  logic                           tcdm_req_i,
  output logic                           tcdm_gnt_o,
  input  logic [31:0]                    tcdm_addr_i,
  input  logic                           tcdm_we_i,
  input  logic signed [INPUT_WIDTH-1:0]  tcdm_wdata_i,
  output logic                           tcdm_rvalid_o,
  output logic signed [OUTPUT_WIDTH-1:0] tcdm_rdata_o,

  input  logic        PSEL,
  input  logic        PENABLE,
  input  logic        PWRITE,
  input  logic [31:0] PADDR,
  input  logic [31:0] PWDATA,
  output logic [31:0] PRDATA,
  output logic        PREADY,
  output logic        PSLVERR,
  output logic        irq_o
);

  ctrl_to_core_t core_ctrl;
  core_to_ctrl_t core_status;
  csr_to_ctrl_t csr_config;
  ctrl_to_csr_t telemetry;
  logic result_valid;
  logic signed [OUTPUT_WIDTH-1:0] result_data;
  logic [ITER_CNT_WIDTH-1:0] full_iter_core;
  logic activation_accept;

  always_comb begin
    full_iter_core = bounded_full_iter(csr_config.full_iter, csr_config.min_iter);

    activation_accept = tcdm_req_i && !tcdm_we_i && telemetry.ready_flag;
    tcdm_gnt_o = telemetry.ready_flag;
    tcdm_rvalid_o = result_valid;
    tcdm_rdata_o = result_data;
  end

  qualification_ctrl u_qualification_ctrl (
    .clk(clk),
    .rst_n(rst_n),
    .x_valid_i(activation_accept),
    .x_i(tcdm_wdata_i),
    .core_ctrl_o(core_ctrl),
    .core_ctrl_i(core_status),
    .csr_i(csr_config),
    .csr_o(telemetry),
    .result_valid_o(result_valid),
    .result_o(result_data)
  );

  cordic_core u_cordic_core (
    .clk(clk),
    .rst_n(rst_n),
    .ctrl_i(core_ctrl),
    .full_iter_i(full_iter_core),
    .round_mode_en_i(1'b1),
    .ctrl_o(core_status),
    .dbg_valid_o(),
    .dbg_full_result_o(),
    .dbg_overflow_o()
  );

  csr_apb u_csr_apb (
    .clk(clk),
    .rst_n(rst_n),
    .PSEL(PSEL),
    .PENABLE(PENABLE),
    .PWRITE(PWRITE),
    .PADDR(PADDR),
    .PWDATA(PWDATA),
    .PRDATA(PRDATA),
    .PREADY(PREADY),
    .PSLVERR(PSLVERR),
    .ctrl_o(csr_config),
    .ctrl_i(telemetry),
    .irq_o(irq_o)
  );

endmodule : cordic_activation_top
