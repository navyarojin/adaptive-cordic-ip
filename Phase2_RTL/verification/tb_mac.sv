`timescale 1ns/1ps
module tb_mac4_stream;
  import activation_reference_pkg::*;
  logic clk=0,rst_n=0,valid_i=0,ready_i=1;
  wire ready_o,valid_o,idle_o;
  logic [31:0] values_i;
  logic [127:0] weights_i,bias_i;
  logic [4:0] shift_i;
  logic [15:0] tag_i;
  logic [3:0] row_active_i=15;
  wire [75:0] values_o;
  wire [15:0] tag_o;
  wire baseline_ready,baseline_valid,baseline_idle;
  wire [75:0] baseline_values;
  wire [15:0] baseline_tag;
  logic [15:0] masks_seen=0;
  integer expected[0:4095][0:3];
  integer tags[0:4095];
  integer accepted=0,retired=0,checks=0,cycle=0,last_accept=-1;
  bit continuous=0,held=0;
  logic [75:0] held_values;
  logic [15:0] held_tag;
  always #5 clk=~clk;
  mac4_stream #(.TAG_WIDTH(16)) dut(.*);
  mac4_stream #(.TAG_WIDTH(16),.ENABLE_GATING(0)) baseline (
    .clk,.rst_n,.valid_i,.ready_o(baseline_ready),.values_i,.weights_i,.bias_i,
    .row_active_i,.shift_i,.tag_i,.valid_o(baseline_valid),.ready_i,
    .values_o(baseline_values),.tag_o(baseline_tag),.idle_o(baseline_idle));
  always @(posedge clk) begin
    logic [15:0] old_product[0:3][0:3];
    logic [16:0] old_pair[0:3][0:1];
    logic [3:0] product_enable,pair_enable;
    product_enable={4{rst_n && dut.advance && valid_i}} & row_active_i;
    pair_enable={4{rst_n && dut.advance && dut.valid_q[0]}} & dut.row_active_q[0];
    for(int r=0;r<4;r++)begin
      for(int c=0;c<4;c++)old_product[r][c]=dut.product_q[r][c];
      for(int c=0;c<2;c++)old_pair[r][c]=dut.pair_q[r][c];
    end
    #1;
    if(rst_n)for(int r=0;r<4;r++)begin
      for(int c=0;c<4;c++)if(!product_enable[r] && dut.product_q[r][c]!==old_product[r][c])$fatal(1,"Disabled product register changed");
      for(int c=0;c<2;c++)if(!pair_enable[r] && dut.pair_q[r][c]!==old_pair[r][c])$fatal(1,"Disabled pair register changed");
    end
  end
  always @(posedge clk) begin
    longint signed total,divisor;
    cycle++;
    if (!rst_n) begin accepted=0; retired=0; held=0; last_accept=-1; end
    else begin
      if(ready_o!==baseline_ready || valid_o!==baseline_valid || idle_o!==baseline_idle)
        $fatal(1,"Gated/ungated handshake mismatch");
      if(valid_o && (values_o!==baseline_values || tag_o!==baseline_tag))
        $fatal(1,"Gated/ungated payload mismatch");
      if (held && (!valid_o || values_o!==held_values || tag_o!==held_tag))
        $fatal(1,"MAC output changed during backpressure");
      held=valid_o && !ready_i; held_values=values_o; held_tag=tag_o;
      if (valid_i && ready_o) begin
        masks_seen[row_active_i]=1;
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
        if(i>=2 && i%3!=0)for(int r=0;r<4;r++)if(!((i>>r)&1))weights_i[r*32 +: 32]=0;
        for(int r=0;r<4;r++)row_active_i[r]=|weights_i[r*32 +: 32];
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
    if(masks_seen!==16'hffff)$fatal(1,"Incomplete row-mask coverage %h",masks_seen);
    $display("PASS MAC4: %0d lane checks; II=1; signed extremes; shifts; random stalls; reset; all 16 row masks; ungated equivalence; register holds",checks);
    $finish;
  end
  initial begin #1000000; $fatal(1,"MAC timeout"); end
endmodule
