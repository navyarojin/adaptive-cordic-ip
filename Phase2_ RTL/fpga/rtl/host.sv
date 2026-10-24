module jupyter_npu #(parameter MEM_FILE = "firmware.mem", parameter int ACTIVATION_LANES = 4,
                     parameter bit STREAMING=0,parameter int STREAM_LANES=4) (
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst_n, FREQ_HZ 25000000" *)
  input wire clk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input wire rst_n,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM CLK" *)
  input wire s_bram_clk,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM RST" *)
  input wire s_bram_rst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM EN" *)
  input wire s_bram_en,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM WE" *)
  input wire [3:0] s_bram_we,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM ADDR" *)
  input wire [11:0] s_bram_addr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM DIN" *)
  input wire [31:0] s_bram_wrdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM DOUT" *)
  output logic [31:0] s_bram_rddata,
  output wire [3:0] led,
  output wire uart_tx,
  input wire stream_en,
  input wire [3:0] stream_we,
  input wire [15:0] stream_addr,
  input wire [31:0] stream_wrdata,
  output wire [31:0] stream_rddata
);
  (* ram_style = "block" *) logic [31:0] mailbox_mem [0:1023];
  initial for (integer i=0;i<1024;i=i+1) mailbox_mem[i]=0;
  wire cpu_en, cpu_we;
  wire [3:0] cpu_be;
  wire [11:0] cpu_addr;
  wire [31:0] cpu_wdata;
  logic [31:0] cpu_rdata;
  wire [31:0] status, detail, cycles;
  wire stream_cpu_en,stream_cpu_we,stream_irq;
  wire [3:0] stream_cpu_be;
  wire [11:0] stream_cpu_addr;
  wire [31:0] stream_cpu_wdata,stream_cpu_rdata;
  if (STREAMING) begin : streaming_system
    stream_mmio #(.LANES(STREAM_LANES)) peripheral (
      .clk,.rst_n,.cpu_en_i(stream_cpu_en),.cpu_we_i(stream_cpu_we),
      .cpu_be_i(stream_cpu_be),.cpu_addr_i(stream_cpu_addr),.cpu_wdata_i(stream_cpu_wdata),
      .cpu_rdata_o(stream_cpu_rdata),.ps_en_i(stream_en),.ps_we_i(stream_we),
      .ps_addr_i(stream_addr),.ps_wdata_i(stream_wrdata),.ps_rdata_o(stream_rddata),.irq_o(stream_irq));
  end else begin : without_streaming
    assign stream_cpu_rdata=0;
    assign stream_irq=0;
    assign stream_rddata=0;
  end
  logic [31:0] ps_ram_q, ps_status_q;
  logic ps_status_sel_q;
  always @(posedge s_bram_clk) begin
    if (s_bram_en) begin
      ps_ram_q <= mailbox_mem[s_bram_addr[11:2]];
      if (s_bram_addr < 12'h100)
        for (integer b=0;b<4;b=b+1)
          if (s_bram_we[b]) mailbox_mem[s_bram_addr[11:2]][8*b +: 8] <= s_bram_wrdata[8*b +: 8];
    end
  end
  always @(posedge clk) begin
    if (cpu_en) begin
      cpu_rdata <= mailbox_mem[cpu_addr[11:2]];
      if (cpu_we && cpu_addr >= 12'h100 && cpu_addr < 12'h200)
        for (integer b=0;b<4;b=b+1)
          if (cpu_be[b]) mailbox_mem[cpu_addr[11:2]][8*b +: 8] <= cpu_wdata[8*b +: 8];
    end
  end
  always @(posedge s_bram_clk) begin
    if (s_bram_rst) begin ps_status_sel_q <= 0; ps_status_q <= 0; end
    else if (s_bram_en) begin
      ps_status_sel_q <= s_bram_addr >= 12'hf00;
      case (s_bram_addr)
        12'hf00: ps_status_q <= 32'h4e505531;
        12'hf04: ps_status_q <= 1;
        12'hf08: ps_status_q <= status;
        12'hf0c: ps_status_q <= detail;
        12'hf10: ps_status_q <= cycles;
        default: ps_status_q <= 0;
      endcase
    end
  end
  always_comb s_bram_rddata = ps_status_sel_q ? ps_status_q : ps_ram_q;
  pynq_npu_soc #(.MEM_FILE(MEM_FILE), .MAILBOX(1),.STREAMING(STREAMING), .ACTIVATION_LANES(ACTIVATION_LANES)) soc (
    .stream_en_o(stream_cpu_en),.stream_we_o(stream_cpu_we),.stream_be_o(stream_cpu_be),
    .stream_addr_o(stream_cpu_addr),.stream_wdata_o(stream_cpu_wdata),
    .stream_rdata_i(stream_cpu_rdata),.stream_irq_i(stream_irq),
    .clk, .rst_n, .mailbox_en_o(cpu_en), .mailbox_we_o(cpu_we),
    .mailbox_be_o(cpu_be), .mailbox_addr_o(cpu_addr), .mailbox_wdata_o(cpu_wdata),
    .mailbox_rdata_i(cpu_rdata), .test_status_o(status), .test_detail_o(detail),
    .cycles_o(cycles), .uart_tx_o(uart_tx), .spi_cs_n_o(), .spi_sck_o(),
    .spi_mosi_o(), .spi_miso_o(), .npu_irq_o()
  );
  assign led = {status[31:16] == 16'hdead, status == 32'h600d600d, cycles[23], rst_n};
endmodule
