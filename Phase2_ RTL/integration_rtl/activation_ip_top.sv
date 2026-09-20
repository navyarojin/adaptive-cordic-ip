



































module activation_ip_top
  import cordic_pkg::*;
(
  input  logic clk,
  input  logic rst_n,

  
  input  logic         PSEL,
  input  logic         PENABLE,
  input  logic         PWRITE,
  input  logic [31:0]  PADDR,
  input  logic [31:0]  PWDATA,
  output logic [31:0]  PRDATA,
  output logic         PREADY,
  output logic         PSLVERR,

  
  input  logic                            x_valid_i,
  input  logic signed [INPUT_WIDTH-1:0]   x_i,
  output logic                            result_valid_o,
  output logic signed [OUTPUT_WIDTH-1:0]  result_o,

  
  input  logic round_mode_en_i,

  
  output logic irq_o,
  output logic ready_o,

  
  output logic                       dbg_enable_o,
  output logic [1:0]                 dbg_activation_mode_o,
  output logic [15:0]                dbg_error_threshold_o,
  output logic [ITER_CNT_WIDTH-1:0]  dbg_iter_budget_o,
  output logic                       dbg_core_start_o,
  output logic                       dbg_sample_mode_o,
  output logic                       dbg_core_valid_o,
  output logic                       dbg_overflow_o,
  output logic [RESIDUAL_WIDTH-1:0]  dbg_residual_o
);

  csr_to_ctrl_t  csr2ctrl;
  ctrl_to_csr_t  ctrl2csr;
  ctrl_to_core_t ctrl2core;
  core_to_ctrl_t core2ctrl;

  csr_apb u_csr_apb (
    .clk     (clk),
    .rst_n   (rst_n),
    .PSEL    (PSEL),
    .PENABLE (PENABLE),
    .PWRITE  (PWRITE),
    .PADDR   (PADDR),
    .PWDATA  (PWDATA),
    .PRDATA  (PRDATA),
    .PREADY  (PREADY),
    .PSLVERR (PSLVERR),
    .ctrl_o  (csr2ctrl),
    .ctrl_i  (ctrl2csr),
    .irq_o   (irq_o)
  );

  qualification_ctrl u_qualification_ctrl (
    .clk            (clk),
    .rst_n          (rst_n),
    .x_valid_i      (x_valid_i),
    .x_i            (x_i),
    .core_ctrl_o    (ctrl2core),
    .core_ctrl_i    (core2ctrl),
    .csr_i          (csr2ctrl),
    .csr_o          (ctrl2csr),
    .result_valid_o (result_valid_o),
    .result_o       (result_o)
  );

  cordic_core u_cordic_core (
    .clk               (clk),
    .rst_n             (rst_n),
    .ctrl_i            (ctrl2core),
    .full_iter_i       (bounded_full_iter(csr2ctrl.full_iter, csr2ctrl.min_iter)),
    .round_mode_en_i   (round_mode_en_i),
    .ctrl_o            (core2ctrl),
    .dbg_valid_o       (),
    .dbg_full_result_o (),
    .dbg_overflow_o    ()
  );

  
  assign dbg_enable_o           = csr2ctrl.enable;
  assign ready_o                = ctrl2csr.ready_flag;
  assign dbg_activation_mode_o  = csr2ctrl.activation_mode;
  assign dbg_error_threshold_o  = csr2ctrl.error_threshold;
  assign dbg_iter_budget_o      = ctrl2core.iter_budget;
  assign dbg_core_start_o       = ctrl2core.start;
  assign dbg_sample_mode_o      = ctrl2core.sample_mode;
  assign dbg_core_valid_o       = core2ctrl.valid;
  assign dbg_overflow_o         = core2ctrl.overflow;
  assign dbg_residual_o         = core2ctrl.residual;

endmodule : activation_ip_top
