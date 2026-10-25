`timescale 1ns/1ps
`ifdef PAD_MODEL_TEST
module pc3c01(input wire CP, output wire CLK); assign CLK=CP; endmodule
module pc3d01(input wire PAD, output wire CIN); assign CIN=PAD; endmodule
module pc3o05(input wire I, output wire PAD); assign PAD=I; endmodule
module tb_pads;
  logic clk=0;
  logic rst_n=0;
  logic cpu_en_i=0;
  logic cpu_we_i=0;
  logic [3:0] cpu_be_i=0;
  logic [11:0] cpu_addr_i=0;
  logic [31:0] cpu_wdata_i=0;
  wire [31:0] cpu_rdata_o;
  logic ps_en_i=0;
  logic [3:0] ps_we_i=0;
  logic [15:0] ps_addr_i=0;
  logic [31:0] ps_wdata_i=0;
  wire [31:0] ps_rdata_o;
  wire irq_o;
  logic compare_core=1;
  logic [31:0] drive_cpu=0,drive_ps=0;
  logic drive_irq=0;
  integer checks=0;
  always #5 clk=~clk;
  wire [31:0] ref_cpu_rdata_o;
  wire [31:0] ref_ps_rdata_o;
  wire ref_irq_o;
  chip dut (
    .clk(clk),
    .rst_n(rst_n),
    .cpu_en_i(cpu_en_i),
    .cpu_we_i(cpu_we_i),
    .cpu_be_i(cpu_be_i),
    .cpu_addr_i(cpu_addr_i),
    .cpu_wdata_i(cpu_wdata_i),
    .cpu_rdata_o(cpu_rdata_o),
    .ps_en_i(ps_en_i),
    .ps_we_i(ps_we_i),
    .ps_addr_i(ps_addr_i),
    .ps_wdata_i(ps_wdata_i),
    .ps_rdata_o(ps_rdata_o),
    .irq_o(irq_o)
  );
  stream_mmio #(.LANES(4)) ref_core (
    .clk(clk),
    .rst_n(rst_n),
    .cpu_en_i(cpu_en_i),
    .cpu_we_i(cpu_we_i),
    .cpu_be_i(cpu_be_i),
    .cpu_addr_i(cpu_addr_i),
    .cpu_wdata_i(cpu_wdata_i),
    .cpu_rdata_o(ref_cpu_rdata_o),
    .ps_en_i(ps_en_i),
    .ps_we_i(ps_we_i),
    .ps_addr_i(ps_addr_i),
    .ps_wdata_i(ps_wdata_i),
    .ps_rdata_o(ref_ps_rdata_o),
    .irq_o(ref_irq_o)
  );
  always @(posedge clk) begin
    #1;
    if (dut.c_clk!==clk) $fatal(1,"Clock-pad mismatch");
    if (compare_core && {cpu_rdata_o,ps_rdata_o,irq_o} !== {ref_cpu_rdata_o,ref_ps_rdata_o,ref_irq_o}) $fatal(1,"Wrapper/core mismatch");
  end
  task check_inputs;
    #1;
    if ({dut.c_rst_n,dut.c_cpu_en_i,dut.c_cpu_we_i,dut.c_cpu_be_i,dut.c_cpu_addr_i,dut.c_cpu_wdata_i,dut.c_ps_en_i,dut.c_ps_we_i,dut.c_ps_addr_i,dut.c_ps_wdata_i} !== {rst_n,cpu_en_i,cpu_we_i,cpu_be_i,cpu_addr_i,cpu_wdata_i,ps_en_i,ps_we_i,ps_addr_i,ps_wdata_i}) $fatal(1,"Input-pad mapping mismatch");
    checks++;
  endtask
  initial begin
    repeat(3) @(negedge clk);
    for (int bit_index=0;bit_index<1;bit_index++) begin
      rst_n=1'(1)<<bit_index;
      check_inputs();
      rst_n='0;
      check_inputs();
    end
    for (int bit_index=0;bit_index<1;bit_index++) begin
      cpu_en_i=1'(1)<<bit_index;
      check_inputs();
      cpu_en_i='0;
      check_inputs();
    end
    for (int bit_index=0;bit_index<1;bit_index++) begin
      cpu_we_i=1'(1)<<bit_index;
      check_inputs();
      cpu_we_i='0;
      check_inputs();
    end
    for (int bit_index=0;bit_index<4;bit_index++) begin
      cpu_be_i=4'(1)<<bit_index;
      check_inputs();
      cpu_be_i='0;
      check_inputs();
    end
    for (int bit_index=0;bit_index<12;bit_index++) begin
      cpu_addr_i=12'(1)<<bit_index;
      check_inputs();
      cpu_addr_i='0;
      check_inputs();
    end
    for (int bit_index=0;bit_index<32;bit_index++) begin
      cpu_wdata_i=32'(1)<<bit_index;
      check_inputs();
      cpu_wdata_i='0;
      check_inputs();
    end
    for (int bit_index=0;bit_index<1;bit_index++) begin
      ps_en_i=1'(1)<<bit_index;
      check_inputs();
      ps_en_i='0;
      check_inputs();
    end
    for (int bit_index=0;bit_index<4;bit_index++) begin
      ps_we_i=4'(1)<<bit_index;
      check_inputs();
      ps_we_i='0;
      check_inputs();
    end
    for (int bit_index=0;bit_index<16;bit_index++) begin
      ps_addr_i=16'(1)<<bit_index;
      check_inputs();
      ps_addr_i='0;
      check_inputs();
    end
    for (int bit_index=0;bit_index<32;bit_index++) begin
      ps_wdata_i=32'(1)<<bit_index;
      check_inputs();
      ps_wdata_i='0;
      check_inputs();
    end
    compare_core=0;
    force dut.c_cpu_rdata_o=drive_cpu;
    force dut.c_ps_rdata_o=drive_ps;
    force dut.c_irq_o=drive_irq;
    for (int bit_index=0;bit_index<32;bit_index++) begin
      drive_cpu=32'b1<<bit_index; drive_ps=~drive_cpu; drive_irq=bit_index[0];
      #1;
      if ({cpu_rdata_o,ps_rdata_o,irq_o} !== {drive_cpu,drive_ps,drive_irq}) $fatal(1,"Output-pad mapping mismatch");
      checks++;
    end
    release dut.c_cpu_rdata_o;
    release dut.c_ps_rdata_o;
    release dut.c_irq_o;
    rst_n=0;
    repeat(4) @(negedge clk);
    compare_core=1; rst_n=1; cpu_en_i=1; cpu_we_i=0; cpu_addr_i=0;
    repeat(3) @(negedge clk);
    if (cpu_rdata_o!==32'h53545231) $fatal(1,"Padded register read failed");
    checks++;
    $display("PASS pads: %0d mapping/reset/read checks; abstract signal-cell models only",checks);
    $finish;
  end
  initial begin #100000; $fatal(1,"Pad test timeout"); end
endmodule
`endif
