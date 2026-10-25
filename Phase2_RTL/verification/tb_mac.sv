`timescale 1ns/1ps
module tb_mac4_stream;
  import activation_reference_pkg::*;
  logic clk=0,rst_n=0,valid_i=0,ready_i=1;
  wire ready_o,valid_o,idle_o;
  logic [31:0] values_i;
  logic [127:0] weights_i,bias_i;
  logic [4:0] shift_i;
  logic [15:0] tag_i;
  wire [75:0] values_o;
  wire [15:0] tag_o;
  integer expected[0:4095][0:3];
  integer tags[0:4095];
  integer accepted=0,retired=0,checks=0,cycle=0,last_accept=-1;
  bit continuous=0,held=0;
  logic [75:0] held_values;
  logic [15:0] held_tag;
  always #5 clk=~clk;
  mac4_stream #(.TAG_WIDTH(16)) dut(.*);
  always @(posedge clk) begin
    longint signed total,divisor;
    cycle++;
    if (!rst_n) begin accepted=0; retired=0; held=0; last_accept=-1; end
    else begin
      if (held && (!valid_o || values_o!==held_values || tag_o!==held_tag))
        $fatal(1,"MAC output changed during backpressure");
      held=valid_o && !ready_i; held_values=values_o; held_tag=tag_o;
      if (valid_i && ready_o) begin
        if (continuous && last_accept>=0 && cycle-last_accept!=1) $fatal(1,"MAC II exceeds one");
        last_accept=cycle;
        for (int r=0;r<4;r++) begin
          total=$signed(bias_i[r*32 +: 32]);
          for (int c=0;c<4;c++) total+=int'($signed(values_i[c*8 +: 8]))*int'($signed(weights_i[(r*4+c)*8 +: 8]));
          divisor=64'sd1<<shift_i;
          expected[accepted][r]=sat(rounded_div(total,divisor),19);
        end
        tags[accepted]=tag_i; accepted++;
      end
      if (valid_o && ready_i) begin
        if (retired>=accepted || tag_o!=tags[retired]) $fatal(1,"MAC tag/order mismatch");
        for (int r=0;r<4;r++) begin
          if ($signed(values_o[r*19 +: 19])!=expected[retired][r])
            $fatal(1,"MAC result %0d lane %0d got %0d expected %0d",retired,r,$signed(values_o[r*19 +: 19]),expected[retired][r]);
          checks++;
        end
        retired++;
      end
    end
  end
  initial begin
    repeat(3) @(negedge clk); rst_n=1;
    for (int phase=0;phase<2;phase++) begin
      for (int i=0;i<1200;i++) begin
        @(negedge clk);
        continuous=i<96;
        valid_i=continuous || $urandom_range(0,3)!=0;
        ready_i=continuous || $urandom_range(0,3)!=0;

        values_i=$urandom; tag_i=16'(i);
        for (int r=0;r<4;r++) begin
          weights_i[r*32 +: 32]=$urandom;
          bias_i[r*32 +: 32]=i<96 ? 0 : $urandom;
        end
        if (i==0) begin values_i=32'h80808080; weights_i={4{32'h80808080}}; end
        if (i==1) bias_i={32'h7fffffff,32'h80000000,32'd1,-32'sd1};
        shift_i=i<96 ? 0 : 5'(i%32);
        #1;
        while (valid_i && !ready_o) begin
          @(negedge clk); ready_i=$urandom_range(0,3)!=0; #1;
        end
      end
      @(negedge clk); continuous=0; valid_i=0; ready_i=1;
      wait(idle_o); @(negedge clk);
      if (accepted!=retired || accepted<96) $fatal(1,"Lost MAC results");

      valid_i=1; ready_i=0; repeat(8) @(negedge clk);
      rst_n=0; repeat(2) @(negedge clk);
      valid_i=0; ready_i=1; rst_n=1;
      repeat(8) @(negedge clk);
      if (valid_o || !idle_o) $fatal(1,"MAC reset failed");
    end
    $display("PASS MAC4: %0d lane checks; II=1; signed extremes; shifts; random stalls; reset",checks);
    $finish;
  end
  initial begin #1000000; $fatal(1,"MAC timeout"); end
endmodule
