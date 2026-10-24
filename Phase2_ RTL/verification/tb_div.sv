`timescale 1ns/1ps
module tb_divider_parallel;
  logic clk=0, rst_n=0, start=0;
  always #5 clk=~clk;
  logic signed [31:0] numerator;
  logic signed [17:0] denominator;
  wire [2:0] busy, done, zero;
  wire signed [31:0] quotient [0:2];
  int cycles, checks=0;
  for (genvar i=0; i<3; i++) begin : g
    fx_signed_divider #(.BITS_PER_CYCLE(i==0 ? 1 : (i==1 ? 3 : 4))) dut
      (.clk(clk), .rst_n(rst_n), .start(start), .numerator(numerator),
       .denominator(denominator), .busy(busy[i]), .done(done[i]),
       .quotient(quotient[i]), .div_by_zero(zero[i]));
  end
  task automatic check(input int signed n, input int signed d);
    longint signed nm, dm, expected;
    logic [2:0] seen;
    nm=n; dm=d;
    if(nm<0) nm=-nm;
    if(dm<0) dm=-dm;
    expected=0;
    if(dm!=0) begin
      expected=nm/dm;
      if(2*(nm%dm)>=dm) expected++;
      if((n<0)!=(d<0)) expected=-expected;
    end
    @(negedge clk); numerator=n; denominator=18'(d); start=1;
    @(negedge clk); start=0;
    seen=0; cycles=0;
    while(seen!=7) begin
      @(negedge clk); cycles++;
      for(int i=0;i<3;i++) if(done[i]) begin
        if(seen[i]) $fatal(1,"Repeated completion");
        seen[i]=1;
        if(quotient[i]!==32'(expected) || zero[i]!=(d==0))
          $fatal(1,"divider %0d n=%0d d=%0d got=%0d expected=%0d",i,n,d,quotient[i],expected);
        if(i==2 && cycles>12) $fatal(1,"Parallel divider latency");
      end
      if(cycles>40) $fatal(1,"Divider timeout");
    end
    checks++;
  endtask
  initial begin
    numerator=0; denominator=0;
    repeat(3) @(negedge clk); rst_n=1;
    for(int n=-128;n<128;n++)
      for(int d=-16;d<16;d++) check(n,d);
    check(32'sh80000000,-1);
    check(32'sh80000000,-131072);
    check(32'sh7fffffff,131071);
    for(int i=0;i<3000;i++) check(int'($urandom),int'($urandom_range(0,262143))-131072);
    @(negedge clk); numerator=123456; denominator=31; start=1;
    @(negedge clk); start=0;
    repeat(3) @(negedge clk); rst_n=0;
    @(negedge clk);
    if(busy!==0 || done!==0) $fatal(1,"Reset while busy");
    rst_n=1;
    check(7654321,-317);
    $display("PASS divider: %0d cases, 1/3/4 bits per cycle, signed rounding, zero denominator, extremes, reset",checks);
    $finish;
  end
endmodule
