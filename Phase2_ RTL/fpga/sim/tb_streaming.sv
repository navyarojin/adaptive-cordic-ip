`timescale 1ns/1ps
module tb_streaming #(parameter int ACTIVATION_LANES = 1,parameter int STREAM_LANES=4);
  import activation_reference_pkg::*;
  logic clk=0, rst_n=0;
  integer cycle=0;
  always @(posedge clk) cycle++;
  always #20 clk=~clk;
  logic en=0;
  logic [3:0] we=0;
  logic [11:0] addr=0;
  logic [31:0] wdata=0;
  wire [31:0] rdata;
  wire [3:0] led;
  logic stream_en=0;
  logic [3:0] stream_we=0;
  logic [15:0] stream_addr=0;
  logic [31:0] stream_wdata=0;
  wire [31:0] stream_rdata;
  task automatic swr(input int a,v,input logic [3:0] mask=15);
    @(negedge clk); stream_en=1; stream_we=mask; stream_addr=16'(a); stream_wdata=32'(v);
    @(negedge clk); stream_en=0; stream_we=0;
  endtask
  task automatic srd(input int a,output int v);
    @(negedge clk); stream_en=1; stream_we=0; stream_addr=16'(a);
    @(negedge clk); v=int'(stream_rdata); stream_en=0;
  endtask
  jupyter_npu #(.ACTIVATION_LANES(ACTIVATION_LANES),.STREAMING(1),.STREAM_LANES(STREAM_LANES)) dut (.clk, .rst_n, .s_bram_clk(clk), .s_bram_rst(!rst_n),
    .s_bram_en(en), .s_bram_we(we), .s_bram_addr(addr), .s_bram_wrdata(wdata),
    .s_bram_rddata(rdata), .led, .uart_tx(), .stream_en(stream_en), .stream_we(stream_we), .stream_addr(stream_addr), .stream_wrdata(stream_wdata), .stream_rddata(stream_rdata));
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
    int v,seq,raw,expected,previous_samples,request_start,job_done;
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
    srd(0,v); if(v!='h53545231) $fatal(1,"Streaming identity");
    srd(4,v); if(v!=((64<<16)|STREAM_LANES)) $fatal(1,"Streaming capabilities");
    if (STREAM_LANES==4) begin
      srd('h34,v); if(v!='h10007) $fatal(1,"Missing fused capability");

      for (int mode=0;mode<4;mode++) begin
        for (int i=0;i<4;i++) for (int lane=0;lane<4;lane++)
          swr('h2000+16*i+4*lane,i*17+lane*11-64);
        wr(4,5); wr(8,mode); wr(12,1); wr(16,14); wr(20,14); wr(24,0); wr(28,0); wr('h70,14);
        wr('h74,1); wr('h78,4); wr('h7c,100+mode);
        wr('h80,2); wr('h84,3); wr('h88,0); wr('h8c,0);
        for (int r=0;r<4;r++) begin wr('h90+4*r,2<<(8*r)); wr('ha0+4*r,r%2==0 ? -1 : 1); end
        seq++; wr(0,seq); wait_ack(seq);
        rd('h108,v); if(v!=0) $fatal(1,"CPU fused command error %0d",v);
        do srd(8,v); while (!(v&'h20000));
        for (int i=0;i<4;i++) for(int lane=0;lane<4;lane++) begin
          raw=2*(i*17+lane*11-64)+(lane%2==0 ? -1 : 1);
          expected=activation_fixed(int'(rounded_div(raw,2)),mode,14);
          srd('h4000+16*i+4*lane,v);
          if(v!=expected) $fatal(1,"CPU fused result mode %0d vector %0d lane %0d got %0d expected %0d",mode,i,lane,v,expected);
        end
        srd('hac,v); if(v!=4) $fatal(1,"CPU fused input counter %0d",v);
        srd('hb0,v); if(v!=4) $fatal(1,"CPU fused output counter %0d",v);
        wr(4,3); seq++; wr(0,seq); wait_ack(seq);
      end
      wr(4,5); wr(12,32); seq++; wr(0,seq); wait_ack(seq);
      rd('h108,v); if(v!=1) $fatal(1,"CPU accepted invalid fused shift");
      $display("PASS CV32 fused mailbox: four activation modes; counters; invalid shift");
      wr(4,7); wr('h74,1); wr('h78,4); wr('h7c,200); seq++; wr(0,seq); wait_ack(seq);
      rd('h108,v); if(v!=6) $fatal(1,"Unloaded model accepted");
      for(int r=0;r<4;r++) begin
        wr('h90+4*r,127<<(8*r)); wr('ha0+4*r,0);
        wr('hb0+4*r,127<<(8*r)); wr('hc0+4*r,0);
      end
      wr(4,6); seq++; wr(0,seq); wait_ack(seq);
      rd('h108,v); if(v!=0) $fatal(1,"Model load failed");
      for(int i=0;i<4;i++) for(int l=0;l<4;l++) swr('h2000+16*i+4*l,i*17+l*11-64);
      wr(4,7); seq++; wr(0,seq); wait_ack(seq);
      rd('h108,v); if(v!=0) $fatal(1,"Model submit failed");
      do srd(8,v); while(!(v&'h20000));
      for(int i=0;i<4;i++) begin
        raw=activation_fixed(127*(i*17-64),0,14);
        raw=int'(rounded_div(raw,128));
        if(raw>127) raw=127; if(raw< -128) raw=-128;
        expected=activation_fixed(127*raw,1,14);
        srd('h6000+4*i,v); if(v!=expected) $fatal(1,"Compact model result mismatch");
      end
      srd('hac,v); if(v!=4) $fatal(1,"Model input count");
      srd('hb0,v); if(v!=4) $fatal(1,"Model output count");
      wr(4,6); seq++; wr(0,seq); wait_ack(seq);
      rd('h108,v); if(v!=7) $fatal(1,"Model reload while bank locked accepted");
      wr(4,3); seq++; wr(0,seq); wait_ack(seq);
      $display("PASS CV32 autonomous model: load/run, unload rejection, compact outputs, counters, reload protection");

    end
    for (int mode=0;mode<4;mode++) begin
      for (int vector_index=0;vector_index<4;vector_index++)
        for (int lane=0;lane<STREAM_LANES;lane++)
          swr('h1000+4*STREAM_LANES*vector_index+4*lane,((vector_index*STREAM_LANES+lane)%32-16)*8192);
      wr(4,2); wr(8,mode); wr(16,6); wr(20,14); wr(24,0); wr(28,1); wr('h70,14);
      wr('h74,0); wr('h78,4); wr('h7c,mode+1);
      wr('h80,2); wr('h84,3); wr('h88,0); wr('h8c,0);
      request_start=cycle;
      seq++; wr(0,seq); wait_ack(seq);
      rd('h108,v); if(v!=0) $fatal(1,"CPU enqueue error %0d",v);
      rd('h144,v); $display("STREAM_HOST_BENCH,%0d,%0d",mode,v);
      do srd(8,v); while (!(v & 'h10000));
      job_done=cycle;
      srd('h1c,v); if ((v&65535)!=mode+1) $fatal(1,"Completion tag");
      for (int vector_index=0;vector_index<4;vector_index++)
        for (int lane=0;lane<STREAM_LANES;lane++) begin
          srd('h3000+4*STREAM_LANES*vector_index+4*lane,v);
          expected=activation_fixed(((vector_index*STREAM_LANES+lane)%32-16)*8192,mode,14);
          if(v!=expected) $fatal(1,"CPU stream result mode=%0d vector=%0d lane=%0d got=%0d expected=%0d",mode,vector_index,lane,v,expected);
        end
      $display("STREAM_E2E_BENCH,%0d,%0d,%0d,%0d",STREAM_LANES,mode,job_done-request_start,cycle-request_start);
      wr(4,3); seq++; wr(0,seq); wait_ack(seq);
      srd(8,v); if(v & 'h30300) $fatal(1,"CPU release failed");
    end
    $display("PASS CV32 streaming: lanes=%0d legacy mailbox regression plus queued streaming jobs in all activation modes",STREAM_LANES);
    $finish;
  end
  initial begin repeat(20000000) @(posedge clk); $fatal(1,"Global timeout"); end
endmodule
