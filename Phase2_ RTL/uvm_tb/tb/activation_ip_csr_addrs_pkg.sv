






package activation_ip_csr_addrs;
  localparam bit [31:0] CONTROL             = 32'h00;
  localparam bit [31:0] STATUS              = 32'h04;
  localparam bit [31:0] SAMPLE_COUNT        = 32'h08;
  localparam bit [31:0] MAX_ERROR           = 32'h0C;
  localparam bit [31:0] FALLBACK_COUNT      = 32'h10;
  localparam bit [31:0] ERROR_THRESHOLD     = 32'h14;
  localparam bit [31:0] SAMPLE_RATE         = 32'h18;
  localparam bit [31:0] INTERRUPT_ENABLE    = 32'h1C;
  localparam bit [31:0] MIN_ITER            = 32'h20;
  localparam bit [31:0] MAX_ITER            = 32'h24;
  localparam bit [31:0] FULL_ITER           = 32'h28;
  localparam bit [31:0] QUALIFICATION_COUNT = 32'h2C;
  localparam bit [31:0] VIOLATION_LIMIT     = 32'h30;
  localparam bit [31:0] UPDATE_INTERVAL     = 32'h34;
  localparam bit [31:0] LUT_CONTROL         = 32'h38;
endpackage : activation_ip_csr_addrs
