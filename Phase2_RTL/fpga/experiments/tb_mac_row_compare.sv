`timescale 1ns/1ps
module tb_mac_row_compare;
  logic clk=0,rst_n=0,valid_i=0,ready_i=1;
  logic [31:0] values_i=0;
  logic [127:0] weights_i=0,bias_i=0;
  logic [3:0] row_active_i=15;
  logic [4:0] shift_i=0;
  logic [15:0] tag_i=0;
  wire [1:0] ready_o,valid_o,idle_o;
  wire [151:0] values_o;
  wire [31:0] tag_o;
  logic warmup_done=0;
  logic [31:0] seed=20261029;
  logic [31:0] input_mem[0:541];
  logic [127:0] weight_mem[0:541],bias_mem[0:541];
  logic end_mem[0:541];
  integer expected[0:4095][0:3],expected_tag[0:4095];
  integer accepted=0,retired=0,checks=0,cycles=0,profile=0;
  logic held=0;
  logic [151:0] held_values;
  logic [31:0] held_tags;
  always #20 clk=~clk;
  mac_row_compare suite(.*);
`ifdef RTL_ACTIVITY
  logic [127:0] operand_bits[0:1],last_operands[0:1];
  logic [255:0] product_bits[0:1],last_products[0:1];
  logic [135:0] pair_bits[0:1],sum_bits[0:1],last_pairs[0:1],last_sums[0:1];
  logic [75:0] last_outputs[0:1];
  integer operand_transitions[0:1]='{0,0},product_transitions[0:1]='{0,0};
  integer pair_transitions[0:1]='{0,0},sum_transitions[0:1]='{0,0},output_transitions[0:1]='{0,0};
  integer measured_cycles=0;
  bit sampled=0;
  function automatic integer count_bits(input logic [255:0] bits_i);
    integer count;
    count=0;
    for(int b=0;b<256;b++)if(bits_i[b])count=count+1;
    return count;
  endfunction
  always_comb begin
    for(int r=0;r<4;r++)begin
      for(int c=0;c<4;c++)begin
        operand_bits[0][(r*4+c)*8+:8]=suite.gated.multiply_values[r][c];
        operand_bits[1][(r*4+c)*8+:8]=suite.ungated.multiply_values[r][c];
        product_bits[0][(r*4+c)*16+:16]=suite.gated.product_q[r][c];
        product_bits[1][(r*4+c)*16+:16]=suite.ungated.product_q[r][c];
      end
      for(int c=0;c<2;c++)begin
        pair_bits[0][(r*2+c)*17+:17]=suite.gated.pair_q[r][c];
        pair_bits[1][(r*2+c)*17+:17]=suite.ungated.pair_q[r][c];
      end
      sum_bits[0][r*34+:34]=suite.gated.sum_q[r];
      sum_bits[1][r*34+:34]=suite.ungated.sum_q[r];
    end
  end
  always @(negedge clk)begin
    #1;
    if(warmup_done)begin
      for(int v=0;v<2;v++)begin
        if($isunknown({operand_bits[v],product_bits[v],pair_bits[v],sum_bits[v],values_o[v*76+:76]}))
          $fatal(1,"Unknown state in RTL switching measurement");
        if(sampled)begin
          operand_transitions[v]+=count_bits({128'd0,operand_bits[v]^last_operands[v]});
          product_transitions[v]+=count_bits(product_bits[v]^last_products[v]);
          pair_transitions[v]+=count_bits({120'd0,pair_bits[v]^last_pairs[v]});
          sum_transitions[v]+=count_bits({120'd0,sum_bits[v]^last_sums[v]});
          output_transitions[v]+=count_bits({180'd0,values_o[v*76+:76]^last_outputs[v]});
        end
        last_operands[v]=operand_bits[v];last_products[v]=product_bits[v];
        last_pairs[v]=pair_bits[v];last_sums[v]=sum_bits[v];last_outputs[v]=values_o[v*76+:76];
      end
      if(sampled)measured_cycles++;
      sampled=1;
    end
  end
`endif
  function automatic logic [31:0] random_word;
    seed=1664525*seed+1013904223;
    return seed;
  endfunction
  always @(posedge clk) begin
    longint signed total,magnitude,rounded;
    cycles++;
    if(!rst_n)begin accepted=0;retired=0;held=0;end
    else begin
      if(ready_o[0]!==ready_o[1] || valid_o[0]!==valid_o[1] || idle_o[0]!==idle_o[1])
        $fatal(1,"Gated/ungated flow mismatch");
      if(held && (valid_o!==2'b11 || values_o!==held_values || tag_o!==held_tags))
        $fatal(1,"Payload changed while stalled");
      held=valid_o==2'b11 && !ready_i;held_values=values_o;held_tags=tag_o;
      if(valid_i && &ready_o)begin
        for(int r=0;r<4;r++)begin
          total=$signed(bias_i[r*32+:32]);
          for(int c=0;c<4;c++)total+=int'($signed(values_i[c*8+:8]))*int'($signed(weights_i[(r*4+c)*8+:8]));
          magnitude=total<0 ? -total : total;
          rounded=shift_i==0 ? magnitude : (magnitude+(64'sd1<<(shift_i-1)))>>shift_i;
          if(total<0)rounded=-rounded;
          expected[accepted][r]=rounded>262143 ? 262143 : (rounded< -262144 ? -262144 : int'(rounded));
        end
        expected_tag[accepted]=tag_i;accepted++;
      end
      if(&valid_o && ready_i)begin
        if(retired>=accepted)$fatal(1,"Unexpected output");
        for(int v=0;v<2;v++)begin
          if(tag_o[v*16+:16]!=expected_tag[retired])$fatal(1,"Tag mismatch");
          for(int r=0;r<4;r++)begin
            if($signed(values_o[v*76+r*19+:19])!=expected[retired][r])
              $fatal(1,"MAC timing mismatch profile=%0d variant=%0d item=%0d row=%0d got=%0d expected=%0d",profile,v,retired,r,$signed(values_o[v*76+r*19+:19]),expected[retired][r]);
            checks++;
          end
        end
        retired++;
      end
    end
  end
  task automatic drive(input logic [31:0] acts,input logic [127:0] weights,bias,input int shift,tag,input bit stalls);
    @(negedge clk);
    values_i=acts;weights_i=weights;bias_i=bias;shift_i=5'(shift);tag_i=16'(tag);valid_i=1;
    for(int r=0;r<4;r++)row_active_i[r]=|weights[r*32+:32];
    ready_i=!stalls || cycles%11<7;
    @(posedge clk);
    while(ready_o!==2'b11)begin @(negedge clk);ready_i=cycles%11<7;@(posedge clk);end
  endtask
  task automatic gap(input int length,input bit churn);
    @(negedge clk);valid_i=0;ready_i=1;
    repeat(length)begin
      if(churn)begin
        values_i=random_word();tag_i=16'(random_word());
        for(int r=0;r<4;r++)begin weights_i[r*32+:32]=random_word();bias_i[r*32+:32]=random_word();end
        row_active_i=15;
      end
      @(negedge clk);
    end
  endtask
  initial begin
    logic [127:0] w,b;
    integer wanted;
    if($test$plusargs("DENSE"))profile=1;
    if($test$plusargs("MASKS"))profile=2;
    if($test$plusargs("IDLE"))profile=3;
    $readmemh("acts.mem",input_mem);$readmemh("weights.mem",weight_mem);
    $readmemh("bias.mem",bias_mem);$readmemh("ends.mem",end_mem);
    repeat(8)@(negedge clk);rst_n=1;
    for(int i=0;i<32;i++)drive(32'h01010101,{16{8'h7f}},0,0,i,0);
    gap(8,0);wait(idle_o==2'b11);warmup_done=1;
    gap(32,0);
    if(profile==0)begin
      for(int i=0;i<542;i++)begin
        drive(input_mem[i],weight_mem[i],bias_mem[i],0,32+i,0);
        if(end_mem[i])gap(104,0);
      end
      wanted=574;
    end else if(profile==3)begin gap(1024,1);wanted=32;end
    else begin
      for(int i=0;i<512;i++)begin
        for(int r=0;r<4;r++)begin
          w[r*32+:32]=(profile==2 && !((i>>r)&1)) ? 0 : random_word();
          b[r*32+:32]=random_word();
        end
        if(i==0)begin w={16{8'h80}};b={32'h80000000,32'h7fffffff,32'd1,-32'sd1};end
        drive(i==0 ? 32'h80808080 : random_word(),w,b,i%32,32+i,profile==2);
        if(profile==2 && i%4==0)gap(3,1);
      end
      wanted=544;
    end
    gap(8,0);wait(idle_o==2'b11);@(negedge clk);
    if(accepted!=wanted || retired!=wanted)$fatal(1,"Missing transactions accepted=%0d retired=%0d wanted=%0d",accepted,retired,wanted);
    $display("PASS MAC_ROW_COMPARE profile=%0d accepted=%0d checked_rows=%0d cycles=%0d",profile,accepted,checks,cycles);
`ifdef RTL_ACTIVITY
    for(int v=0;v<2;v++)$display("SWITCH_ROW,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",profile,v,measured_cycles,
      operand_transitions[v],product_transitions[v],pair_transitions[v],sum_transitions[v],output_transitions[v]);
`endif
    $finish;
  end
  initial begin #2000000;$fatal(1,"MAC comparison timeout");end
endmodule
