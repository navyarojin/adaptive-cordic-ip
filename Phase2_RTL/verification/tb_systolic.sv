`timescale 1ns/1ps
module tb_systolic_param;
  logic clk=0;
  logic [2:0] finished='0;
  always #5 clk=~clk;
  for (genvar d=0; d<3; d++) begin : g
    localparam int N = d==0 ? 4 : (d==1 ? 8 : 16);
    logic rst_n=0;
    logic clear=0, load=0, valid=0;
    logic signed [N*N*8-1:0] weights='0;
    logic signed [N*8-1:0] acts='0;
    wire ready, out_valid;
    wire signed [N*24-1:0] sums;
    integer expected [N];
    integer checks=0;
    integer elapsed_cycles;
    integer w, a;
    zero_aware_systolic_npu_param #(.ARRAY_DIM(N)) dut (
      .clk, .rst_n, .clear_i(clear), .load_weights_i(load), .weights_i(weights),
      .in_valid_i(valid), .activations_i(acts), .ready_o(ready),
      .out_valid_o(out_valid), .accumulations_o(sums));
    initial begin
      repeat(3) @(negedge clk); rst_n=1;
      for (int r=0;r<N;r++) expected[r]=0;
      for (int job=0;job<120;job++) begin
        @(negedge clk);
        clear=(job%3==0);
        if (clear) for (int r=0;r<N;r++) expected[r]=0;
        @(negedge clk); clear=0; load=1;
        for (int r=0;r<N;r++) begin
          for (int c=0;c<N;c++) begin
            w=((job*37+r*71+c*19)%256)-128;
            if (job%5==0) w=-128;
            if (job%5==1) w=127;
            weights[(r*N+c)*8 +: 8]=8'(w);
          end
        end
        for (int c=0;c<N;c++) begin
          a=((job*53+c*29)%256)-128;
          if (job%5==0) a=-128;
          if (job%5==1) a=127;
          if (job%5==2 && c%2==0) a=0;
          acts[c*8 +: 8]=8'(a);
        end
        for (int r=0;r<N;r++)
          for (int c=0;c<N;c++)
            expected[r]+=$signed(weights[(r*N+c)*8 +: 8])*$signed(acts[c*8 +: 8]);
        @(negedge clk); load=0; valid=1;
        @(negedge clk); valid=0;
        elapsed_cycles=0;
        while (!out_valid) begin
          if (elapsed_cycles>2*N+2) $fatal(1,"MAC timeout N=%0d",N);
          @(negedge clk); elapsed_cycles++;
        end
        if (elapsed_cycles!=2*N) $fatal(1,"Unexpected latency N=%0d cycles=%0d",N,elapsed_cycles);
        for (int r=0;r<N;r++) begin
          if ($signed(sums[r*24 +: 24]) != expected[r])
            $fatal(1,"N=%0d job=%0d row=%0d sum=%0d expected=%0d",N,job,r,$signed(sums[r*24 +: 24]),expected[r]);
          checks++;
        end
      end
      @(negedge clk); valid=1;
      @(negedge clk); valid=0;
      repeat(2) @(negedge clk);
      clear=1;
      @(negedge clk); clear=0;
      repeat(2*N+2) begin
        @(negedge clk);
        if (out_valid || sums!='0 || !ready) $fatal(1,"Clear failed N=%0d",N);
      end
      valid=1;
      @(negedge clk); valid=0;
      repeat(2) @(negedge clk);
      rst_n=0;
      @(negedge clk); rst_n=1;
      repeat(2*N+2) begin
        @(negedge clk);
        if (out_valid || sums!='0 || !ready) $fatal(1,"Reset failed N=%0d",N);
      end
      $display("PASS systolic N=%0d checks=%0d measured latency=%0d",N,checks,elapsed_cycles);
      finished[d]=1;
    end
  end
  initial begin
    wait(&finished);
    $display("PASS parameterized systolic arrays: 4x4, 8x8, and 16x16");
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1,"Systolic regression timeout");
  end
endmodule
