`timescale 1ns/1ps

module tb_cordic_activation_top;
  logic clk;
  logic rst_n;
  logic tcdm_req_i;
  logic tcdm_gnt_o;
  logic [31:0] tcdm_addr_i;
  logic tcdm_we_i;
  logic signed [18:0] tcdm_wdata_i;
  logic tcdm_rvalid_o;
  logic signed [15:0] tcdm_rdata_o;
  logic PSEL;
  logic PENABLE;
  logic PWRITE;
  logic [31:0] PADDR;
  logic [31:0] PWDATA;
  logic [31:0] PRDATA;
  logic PREADY;
  logic PSLVERR;
  logic irq_o;
  logic signed [15:0] result_q;

  cordic_activation_top dut (
    .clk(clk),
    .rst_n(rst_n),
    .tcdm_req_i(tcdm_req_i),
    .tcdm_gnt_o(tcdm_gnt_o),
    .tcdm_addr_i(tcdm_addr_i),
    .tcdm_we_i(tcdm_we_i),
    .tcdm_wdata_i(tcdm_wdata_i),
    .tcdm_rvalid_o(tcdm_rvalid_o),
    .tcdm_rdata_o(tcdm_rdata_o),
    .PSEL(PSEL),
    .PENABLE(PENABLE),
    .PWRITE(PWRITE),
    .PADDR(PADDR),
    .PWDATA(PWDATA),
    .PRDATA(PRDATA),
    .PREADY(PREADY),
    .PSLVERR(PSLVERR),
    .irq_o(irq_o)
  );

  always #5 clk = ~clk;

  task automatic apb_write(
    input logic [31:0] addr,
    input logic [31:0] data
  );
    begin
      @(negedge clk);
      PSEL <= 1'b1;
      PENABLE <= 1'b0;
      PWRITE <= 1'b1;
      PADDR <= addr;
      PWDATA <= data;
      @(negedge clk);
      PENABLE <= 1'b1;
      @(posedge clk);
      if (!PREADY || PSLVERR)
        $fatal(1, "APB write failed at address %h", addr);
      @(negedge clk);
      PSEL <= 1'b0;
      PENABLE <= 1'b0;
      PWRITE <= 1'b0;
      PADDR <= '0;
      PWDATA <= '0;
    end
  endtask

  task automatic submit_activation(
    input logic signed [18:0] value,
    output logic signed [15:0] result
  );
    begin
      wait (tcdm_gnt_o);
      @(negedge clk);
      tcdm_req_i <= 1'b1;
      tcdm_we_i <= 1'b0;
      tcdm_wdata_i <= value;
      @(posedge clk);
      @(negedge clk);
      tcdm_req_i <= 1'b0;
      tcdm_wdata_i <= '0;
      wait (tcdm_rvalid_o);
      result = tcdm_rdata_o;
      @(posedge clk);
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    tcdm_req_i = 1'b0;
    tcdm_addr_i = '0;
    tcdm_we_i = 1'b0;
    tcdm_wdata_i = '0;
    PSEL = 1'b0;
    PENABLE = 1'b0;
    PWRITE = 1'b0;
    PADDR = '0;
    PWDATA = '0;

    $dumpfile("phase2_activation_top.vcd");
    $dumpvars(0, tb_cordic_activation_top);

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    apb_write(32'h14, 32'd4);
    apb_write(32'h18, 32'd1);
    apb_write(32'h20, 32'd6);
    apb_write(32'h24, 32'd14);
    apb_write(32'h28, 32'd14);
    apb_write(32'h2C, 32'd2);
    apb_write(32'h30, 32'd2);
    apb_write(32'h34, 32'd0);

    apb_write(32'h00, 32'h00000001);
    submit_activation(19'sd16384, result_q);
    $display("tanh(1.0): fixed result = %0d", result_q);

    apb_write(32'h00, 32'h00000003);
    submit_activation(19'sd16384, result_q);
    $display("sigmoid(1.0): fixed result = %0d", result_q);

    apb_write(32'h00, 32'h00000005);
    submit_activation(-19'sd16384, result_q);
    if (result_q !== 16'sd0)
      $fatal(1, "ReLU negative input produced %0d", result_q);

    apb_write(32'h00, 32'h00000007);
    submit_activation(19'sd8192, result_q);
    if (result_q !== 16'sd8192)
      $fatal(1, "Linear input produced %0d", result_q);

    $display("PASS: integration waveform written to phase2_activation_top.vcd");
    $finish;
  end

  initial begin
    #500000;
    $fatal(1, "Timeout waiting for activation result");
  end
endmodule : tb_cordic_activation_top
