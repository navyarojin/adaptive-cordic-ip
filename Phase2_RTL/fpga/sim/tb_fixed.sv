`timescale 1ns/1ps
module tb_fixed_evaluation;
  import activation_reference_pkg::*;
  logic clk=0,rst_n=0,valid_i=0,ready_i=1;
  logic [75:0] values_i;
  logic [1:0] mode_i;
  logic [15:0] tag_i;
  wire ready_o,valid_o;
  wire [63:0] results_o;
  wire [15:0] tag_o;
  logic [18:0] inputs[0:49151];
  int cycle=0,accepted=0,retired=0,first_in,first_out,last_out,steady_first,workload;
  bit measuring=0;
  always #20 clk=~clk;
  fixed_activation_baseline dut(.*);
  always @(posedge clk) begin
    cycle++;
    if(measuring && rst_n) begin
      if(valid_i && ready_o) begin if(accepted==0) first_in=cycle; accepted++; end
      if(valid_o && ready_i) begin
        if(tag_o!=retired) $fatal(1,"Fixed baseline ordering");
        for(int l=0;l<4;l++)
          if($signed(results_o[l*16 +: 16])!=activation_fixed($signed(inputs[(workload*2048+retired)*4+l]),mode_i,14))
            $fatal(1,"Fixed baseline reference mismatch");
        if(retired==0) first_out=cycle;
        if(retired==256) steady_first=cycle;
        last_out=cycle; retired++;
      end
    end
  end
  initial begin
    $readmemh("stimulus.mem",inputs);
    for(int mode=0;mode<2;mode++) for(int w=0;w<6;w++) begin
      @(negedge clk); rst_n=0; measuring=0; valid_i=0; mode_i=2'(mode); workload=w;
      repeat(3) @(negedge clk); rst_n=1; measuring=1; accepted=0; retired=0;
      for(int v=0;v<2048;v++) begin
        @(negedge clk); valid_i=1; tag_i=16'(v);
        for(int l=0;l<4;l++) values_i[l*19 +: 19]=inputs[(w*2048+v)*4+l];
        #1; if(!ready_o) $fatal(1,"Fixed baseline failed II=1");
      end
      @(negedge clk); valid_i=0; wait(retired==2048); @(negedge clk); measuring=0;
      if(accepted!=2048) $fatal(1,"Fixed baseline input count");
      $display("FIXED_EVAL,%0d,%0d,%0d,%0d,%0d",mode,w,first_out-first_in,last_out-first_in+1,last_out-steady_first+1);
    end
    $display("PASS fixed-only baseline: 98304 outputs; two functions; six matched workloads; II=1");
    $finish;
  end
  initial begin #20000000; $fatal(1,"Fixed baseline timeout"); end
endmodule
