`timescale 1ns/1ps
module tb_jupyter #(parameter int ACTIVATION_LANES = 4);
  import activation_reference_pkg::*;
  logic clk=0, rst_n=0;
  always #20 clk=~clk;
  logic en=0;
  logic [3:0] we=0;
  logic [11:0] addr=0;
  logic [31:0] wdata=0;
  wire [31:0] rdata;
  wire [3:0] led;
  jupyter_npu #(.ACTIVATION_LANES(ACTIVATION_LANES)) dut (.clk, .rst_n, .s_bram_clk(clk), .s_bram_rst(!rst_n),
    .s_bram_en(en), .s_bram_we(we), .s_bram_addr(addr), .s_bram_wrdata(wdata),
    .s_bram_rddata(rdata), .led, .uart_tx());
  task automatic wr(input int a, v, input logic [3:0] mask=15);
    @(negedge clk); en=1; we=mask; addr=12'(a); wdata=32'(v);
    @(negedge clk); en=0; we=0;
  endtask
  task automatic rd(input int a, output int v);
    @(negedge clk); en=1; we=0; addr=12'(a);
    @(negedge clk); v=int'(rdata); en=0;
  endtask
  task automatic wait_ack(input int seq);
    int v;
    for (int i=0;i<1000000;i++) begin
      rd('h100,v);
      if (v==seq) return;
      if (led[3]) $fatal(1,"Firmware failed %h",dut.detail);
    end
    $fatal(1,"Mailbox timeout seq=%0d",seq);
  endtask
  initial begin
    int v,seq,raw,expected,previous_samples;
    repeat(8) @(negedge clk); rst_n=1;
    wait(led[2]);
    do rd('h104,v); while(v!=1);
    rd('hf00,v); if (v!='h4e505531) $fatal(1,"Mailbox identity");
    rd('hf0c,v); if (v!=204) $fatal(1,"Boot checks %0d",v);
    wr('hf00,0); rd('hf00,v); if (v!='h4e505531) $fatal(1,"Identity write protection");
    seq=0;
    for (int mode=0;mode<4;mode++) begin
      wr(4,1); wr(8,mode); wr(12,0); wr(16,14); wr(20,14); wr(24,0); wr(28,1); wr('h70,14);
      for (int i=0;i<16;i++) wr('h20+4*i,i%7-3);
      for (int i=0;i<4;i++) wr('h60+4*i,i+1);
      seq++; wr(0,seq); wait_ack(seq);
      rd('h104,v); if (v!=3) $fatal(1,"Mailbox state %0d",v);
      rd('h108,v); if (v!=0) $fatal(1,"Mailbox error %0d",v);
      rd('h140,v); if (v!=5) $fatal(1,"CPU checks %0d",v);
      rd('h144,v); $display("HOST_BENCH,%0d,%0d,%0d",ACTIVATION_LANES,mode,v);
      rd('h148,v);
      if (mode>0 && v-previous_samples!=(mode<2 ? 4 : 0)) $fatal(1,"Aggregated sample delta %0d",v-previous_samples);
      previous_samples=v;
      for (int r=0;r<4;r++) begin
        raw=0;
        for (int c=0;c<4;c++) raw+=((r*4+c)%7-3)*(c+1);
        rd('h120+4*r,v); if(v!=raw) $fatal(1,"Raw result mode %0d row %0d",mode,r);
        expected=activation_fixed(raw,mode,14);
        rd('h130+4*r,v); if(v!=expected) $fatal(1,"Activation mode %0d row %0d got %0d expected %0d",mode,r,v,expected);
      end
    end
    wr(8,0); wr(16,6); wr(20,10);
    for (int i=0;i<16;i++) wr('h20+4*i,100);
    for (int i=0;i<4;i++) wr('h60+4*i,i==0 ? 1:0);
    seq++; wr(0,seq); wait_ack(seq);
    for (int r=0;r<4;r++) begin
      rd('h130+4*r,v); if(v!=activation_fixed(100,0,14)) $fatal(1,"Adaptive fallback result");
    end
    wr('h100,999); rd('h100,v); if(v!=seq) $fatal(1,"Response write protection");
    wr(8,7); seq++; wr(0,seq); wait_ack(seq);
    rd('h108,v); if(v!=1) $fatal(1,"Invalid config not rejected");
    wr(8,3); wr('h20,200); seq++; wr(0,seq); wait_ack(seq);
    rd('h108,v); if(v!=2) $fatal(1,"Invalid operand not rejected");
    wr('h20,0); wr('h20,'h123456aa,1); rd('h20,v);
    if(v!='haa) $fatal(1,"Mailbox byte write");
    @(negedge clk); rst_n=0;
    repeat(8) @(negedge clk); rst_n=1;
    wait(led[2]); do rd('h104,v); while(v!=1);
    rd('h100,v); if(v!=seq) $fatal(1,"Stale request replay after reset");
    wr('h20,1); seq++; wr(0,seq); wait_ack(seq);
    rd('h108,v); if(v!=0) $fatal(1,"Request after reset");
    $display("PASS Jupyter mailbox: four activation modes, CPU checks, malformed requests, byte enables, ownership, reset and subsequent request");
    $finish;
  end
  initial begin repeat(20000000) @(posedge clk); $fatal(1,"Global timeout"); end
endmodule
