module pynq_npu_soc #(parameter MEM_FILE = "firmware.mem",
                      parameter integer CLK_HZ = 25000000,
                      parameter bit MAILBOX = 0,
                      parameter bit STREAMING = 0,
                      parameter int ACTIVATION_LANES = 4) (
  input logic clk, rst_n,
  output wire stream_en_o,stream_we_o,
  output wire [3:0] stream_be_o,
  output wire [11:0] stream_addr_o,
  output wire [31:0] stream_wdata_o,
  input wire [31:0] stream_rdata_i,
  input wire stream_irq_i,
  output wire mailbox_en_o, mailbox_we_o,
  output wire [3:0] mailbox_be_o,
  output wire [11:0] mailbox_addr_o,
  output wire [31:0] mailbox_wdata_o,
  input wire [31:0] mailbox_rdata_i,
  output logic [31:0] test_status_o, test_detail_o,
  output logic [31:0] cycles_o,
  output wire uart_tx_o,
  output wire spi_cs_n_o, spi_sck_o, spi_mosi_o, spi_miso_o,
  output wire npu_irq_o
);
  logic i_req, i_gnt, i_valid, d_req, d_gnt, d_valid, d_we;
  logic [3:0] d_be;
  logic [31:0] i_addr, i_data, d_addr, d_wdata, d_data;
  logic [31:0] ram_i, ram_d, mmio_data_q;
  logic i_ram_q, d_ram_q, d_mailbox_q,d_stream_q;
  wire stream_sel=STREAMING && d_addr[31:12]==20'h10003;
  assign stream_en_o=d_gnt && stream_sel;
  assign stream_we_o=d_we;
  assign stream_be_o=d_be;
  assign stream_addr_o=d_addr[11:0];
  assign stream_wdata_o=d_wdata;
  wire mailbox_sel = MAILBOX && d_addr[31:12] == 20'h10002;
  assign mailbox_en_o = d_gnt && mailbox_sel;
  assign mailbox_we_o = d_we;
  assign mailbox_be_o = d_be;
  assign mailbox_addr_o = d_addr[11:0];
  assign mailbox_wdata_o = d_wdata;
  wire i_ram = i_addr[31:16] == 0;
  wire d_ram = d_addr[31:16] == 0;
  wire spi_sel = d_addr[31:8] == 24'h100000;
  wire sys_sel = d_addr[31:8] == 24'h100010;
  wire full_write = d_req && d_we && &d_be && d_addr[1:0] == 0;
  logic [79:0] spi_tx_q;
  wire [79:0] spi_rx;
  logic [15:0] spi_div_q;
  logic spi_start_q, spi_done_q, spi_reject_q;
  wire spi_busy, spi_done;
  wire npu_miso, npu_miso_oe;
  logic [3:0] npu_reset_q;
  logic [31:0] fault_q;
  logic uart_start_q;
  logic [7:0] uart_data_q;
  wire uart_busy;
  wire [31:0] irqs = {15'b0,(STREAMING && stream_irq_i),4'b0,npu_irq_o,11'b0};

  assign i_gnt = i_req && rst_n;
  assign d_gnt = d_req && rst_n;
  assign i_data = i_ram_q ? ram_i : 32'h00100073;
  assign d_data = d_ram_q ? ram_d : d_mailbox_q ? mailbox_rdata_i : d_stream_q ? stream_rdata_i : mmio_data_q;
  assign spi_miso_o = npu_miso_oe ? npu_miso : 1'b0;

  cv32e40p_top #(.COREV_PULP(0), .COREV_CLUSTER(0), .FPU(0)) cpu (
    .clk_i(clk), .rst_ni(rst_n), .pulp_clock_en_i(1'b0), .scan_cg_en_i(1'b0),
    .boot_addr_i(32'h1000), .mtvec_addr_i(32'h0), .dm_halt_addr_i(32'h0),
    .hart_id_i(32'h0), .dm_exception_addr_i(32'h0),
    .instr_req_o(i_req), .instr_gnt_i(i_gnt), .instr_rvalid_i(i_valid),
    .instr_addr_o(i_addr), .instr_rdata_i(i_data),
    .data_req_o(d_req), .data_gnt_i(d_gnt), .data_rvalid_i(d_valid),
    .data_we_o(d_we), .data_be_o(d_be), .data_addr_o(d_addr),
    .data_wdata_o(d_wdata), .data_rdata_i(d_data), .irq_i(irqs),
    .irq_ack_o(), .irq_id_o(), .debug_req_i(1'b0), .debug_havereset_o(),
    .debug_running_o(), .debug_halted_o(), .fetch_enable_i(rst_n), .core_sleep_o()
  );
  host_ram #(.INIT_FILE(MEM_FILE)) ram (
    .clk, .i_en(i_gnt && i_ram), .i_addr(i_addr[15:0]), .i_rdata(ram_i),
    .d_en(d_gnt && d_ram), .d_we, .d_be, .d_addr(d_addr[15:0]), .d_wdata,
    .d_rdata(ram_d)
  );
  spi_master80 spi_master (.clk, .rst_n, .start_i(spi_start_q), .tx_i(spi_tx_q),
    .half_period_i(spi_div_q), .busy_o(spi_busy), .done_o(spi_done), .rx_o(spi_rx),
    .cs_n_o(spi_cs_n_o), .sck_o(spi_sck_o), .mosi_o(spi_mosi_o), .miso_i(spi_miso_o));
  npu_spi_top #(.ACTIVATION_LANES(ACTIVATION_LANES)) npu (.clk, .rst_n(rst_n && (npu_reset_q == 0)),
    .spi_cs_n_i(spi_cs_n_o), .spi_sck_i(spi_sck_o), .spi_mosi_i(spi_mosi_o),
    .spi_miso_o(npu_miso), .spi_miso_oe_o(npu_miso_oe), .irq_o(npu_irq_o));
  uart_tx #(.CLK_HZ(CLK_HZ)) uart (.clk, .rst_n, .start_i(uart_start_q),
    .data_i(uart_data_q), .busy_o(uart_busy), .tx_o(uart_tx_o));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      i_valid <= 0; d_valid <= 0; i_ram_q <= 0; d_ram_q <= 0; d_mailbox_q <= 0; mmio_data_q <= 0;
      d_stream_q<=0;
      spi_tx_q <= 0; spi_div_q <= 8; spi_start_q <= 0; spi_done_q <= 0;
      spi_reject_q <= 0; npu_reset_q <= 15; fault_q <= 0;
      uart_start_q <= 0; uart_data_q <= 0; cycles_o <= 0;
      test_status_o <= 0; test_detail_o <= 0;
    end else begin
      i_valid <= i_gnt; d_valid <= d_gnt;
      i_ram_q <= i_ram; d_ram_q <= d_ram;
      d_mailbox_q <= mailbox_sel;
      d_stream_q<=stream_sel;
      cycles_o <= cycles_o + 1'b1;
      spi_start_q <= 0; uart_start_q <= 0;
      if (npu_reset_q != 0) npu_reset_q <= npu_reset_q - 1'b1;
      if (spi_done) spi_done_q <= 1;
      if (i_gnt && !i_ram) fault_q <= i_addr;
      if (d_gnt && !d_ram && !mailbox_sel && !stream_sel) begin
        mmio_data_q <= 0;
        if (spi_sel) begin
          case (d_addr[7:0])
            8'h00: mmio_data_q <= spi_tx_q[31:0];
            8'h04: mmio_data_q <= spi_tx_q[63:32];
            8'h08: mmio_data_q <= {16'b0,spi_tx_q[79:64]};
            8'h10: mmio_data_q <= {29'b0,spi_reject_q,spi_done_q,spi_busy | spi_start_q};
            8'h14: mmio_data_q <= spi_rx[31:0];
            8'h18: mmio_data_q <= spi_rx[63:32];
            8'h1c: mmio_data_q <= {16'b0,spi_rx[79:64]};
            8'h20: mmio_data_q <= {16'b0,spi_div_q};
            8'h24: mmio_data_q <= {28'b0,npu_reset_q};
            8'h0c: ;
            default: begin mmio_data_q <= 32'hbad00001; fault_q <= d_addr; end
          endcase
          if (full_write) case (d_addr[7:0])
            8'h00: spi_tx_q[31:0] <= d_wdata;
            8'h04: spi_tx_q[63:32] <= d_wdata;
            8'h08: spi_tx_q[79:64] <= d_wdata[15:0];
            8'h0c: if (d_wdata[0]) begin
              if (!spi_busy && !spi_start_q && npu_reset_q == 0) begin
                spi_start_q <= 1; spi_done_q <= 0; spi_reject_q <= 0;
              end else spi_reject_q <= 1;
            end
            8'h20: spi_div_q <= d_wdata[15:0] < 8 ? 16'd8 : d_wdata[15:0];
            8'h24: if (d_wdata[0] && !spi_busy && !spi_start_q) npu_reset_q <= 15;
            default: ;
          endcase
        end else if (sys_sel) begin
          case (d_addr[7:0])
            8'h00: mmio_data_q <= test_status_o;
            8'h04: mmio_data_q <= test_detail_o;
            8'h08: mmio_data_q <= cycles_o;
            8'h0c: mmio_data_q <= {31'b0,npu_irq_o};
            8'h14: mmio_data_q <= {31'b0,uart_busy | uart_start_q};
            8'h18: mmio_data_q <= fault_q;
            8'h10: ;
            default: begin mmio_data_q <= 32'hbad00002; fault_q <= d_addr; end
          endcase
          if (full_write) case (d_addr[7:0])
            8'h00: test_status_o <= d_wdata;
            8'h04: test_detail_o <= d_wdata;
            8'h10: if (!uart_busy && !uart_start_q) begin uart_start_q <= 1; uart_data_q <= d_wdata[7:0]; end
            8'h18: fault_q <= 0;
            default: ;
          endcase
        end else begin mmio_data_q <= 32'hbad0add0; fault_q <= d_addr; end
        if (d_we && !full_write) fault_q <= d_addr;
      end
    end
  end
endmodule
