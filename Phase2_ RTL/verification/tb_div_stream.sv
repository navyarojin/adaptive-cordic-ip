`timescale 1ns/1ps
module tb_divider_stream;
  logic clk=0, rst_n=0, valid_i=0, ready_i=1;
  logic signed [31:0] numerator_i;
  logic signed [17:0] denominator_i;
  logic [15:0] tag_i;
  wire ready_o, valid_o, zero_o;
  wire signed [31:0] quotient_o;
  wire [15:0] tag_o;
  integer sent=0, received=0, cycle=0;
  integer expected [0:8191];
  bit zero_expected [0:8191];
  integer tags [0:8191];
  logic stalled=0;
  logic [48:0] held;
  longint signed n,d,q;
  always #5 clk=~clk;
  fx_signed_divider_stream #(.TAG_WIDTH(16)) dut (
    .clk,.rst_n,.valid_i,.ready_o,.numerator_i,.denominator_i,.tag_i,
    .valid_o,.ready_i,.quotient_o,.div_by_zero_o(zero_o),.tag_o);
  always @(posedge clk) begin
    if (!rst_n) begin
      sent=0;
      received=0;
      stalled=0;
    end else begin
      if (stalled && (!valid_o || {quotient_o,zero_o,tag_o}!==held))
        $fatal(1,"Output changed under backpressure");
      stalled=valid_o && !ready_i;
      held={quotient_o,zero_o,tag_o};
      if (valid_i && ready_o) begin
        n=numerator_i; d=denominator_i;
        q=0;
        if (d!=0) begin
          q=((n<0 ? -n:n)+(d<0 ? -d:d)/2)/(d<0 ? -d:d);
          if ((n<0)!=(d<0)) q=-q;
        end
        expected[sent]=32'(q);
        zero_expected[sent]=(d==0);
        tags[sent]=tag_i;
        sent++;
      end
      if (valid_o && ready_i) begin
        if (received>=sent) $fatal(1,"Unexpected output");
        if (quotient_o!==expected[received] || zero_o!==zero_expected[received] || tag_o!=tags[received])
          $fatal(1,"Divider index=%0d got=%0d expected=%0d tag=%0d",received,quotient_o,expected[received],tag_o);
        received++;
      end
    end
  end
  task automatic batch(input bit backpressure);
    for (int i=0;i<2048;i++) begin
      @(negedge clk);
      valid_i=1;
      numerator_i=32'((64'(i)*93857311)^64'h80000000);
      denominator_i=18'(i*7139);
      if (i%19==0) denominator_i=0;
      if (i%19==1) denominator_i=1;
      if (i%19==2) denominator_i=-1;
      if (i%19==3) denominator_i=-131072;
      tag_i=16'(i);
      ready_i=!backpressure || i%7!=0;
      #1;
      if (!ready_o) begin
        @(negedge clk);
        ready_i=1;
        #1;
      end
      while (!ready_o) @(negedge clk);
    end
    @(negedge clk); valid_i=0; ready_i=1;
    wait(received==sent);
    repeat(2) @(negedge clk);
  endtask
  initial begin
    repeat(3) @(negedge clk); rst_n=1;
    batch(0);
    if (received!=2048) $fatal(1,"Missing continuous inputs");
    batch(1);
    if (received!=4096) $fatal(1,"Missing stalled inputs");
    @(negedge clk); valid_i=1;
    repeat(8) @(negedge clk);
    rst_n=0; valid_i=0;
    repeat(2) @(negedge clk); rst_n=1;
    repeat(40) begin
      @(negedge clk);
      if (valid_o) $fatal(1,"Reset did not flush pipeline");
    end
    $display("PASS streaming divider: 4096 signed/rounding/zero/tag checks, backpressure and reset flush");
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1,"Streaming divider timeout");
  end
endmodule
