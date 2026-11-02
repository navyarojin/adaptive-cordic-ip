`timescale 1ns/1ps
module tb_isolation;
`ifdef PHY_NETLIST
  localparam int CORPUS_JOBS=16,OVERFLOW_JOBS=140;
`else
  localparam int CORPUS_JOBS=128,OVERFLOW_JOBS=300;
`endif
  logic clk=0,rst_n=0,clear_i=0,load_weights_i=0,in_valid_i=0;
  logic signed [127:0] weights_i=0;
  logic signed [31:0] activations_i=0;
  wire [4:0] ready,valid;
  wire signed [95:0] result[0:4];
  logic measure=0;
  integer case_id=0,selected_case=-1;
  integer checks=0,jobs=0,elapsed=0,latency_min=999,latency_max=0;
  logic [31:0] seed;
  longint operand_toggles[0:7][0:4],product_toggles[0:7][0:4];
  wire [63:0] pe_operand_toggles[0:4][0:3][0:3],pe_product_toggles[0:4][0:3][0:3];
  integer expected[0:3];
  integer zeros,total_activations;
  always #20 clk=~clk;
  zero_aware_systolic_npu_param legacy(.clk,.rst_n,.clear_i,.load_weights_i,.weights_i,.in_valid_i,.activations_i,.ready_o(ready[0]),.out_valid_o(valid[0]),.accumulations_o(result[0]));
  ungated_systolic_npu_param plain(.clk,.rst_n,.clear_i,.load_weights_i,.weights_i,.in_valid_i,.activations_i,.ready_o(ready[1]),.out_valid_o(valid[1]),.accumulations_o(result[1]));
  retained_systolic_npu_param retained(.clk,.rst_n,.clear_i,.load_weights_i,.weights_i,.in_valid_i,.activations_i,.ready_o(ready[2]),.out_valid_o(valid[2]),.accumulations_o(result[2]));
  zero_hold_systolic_npu_param isolated(.clk,.rst_n,.clear_i,.load_weights_i,.weights_i,.in_valid_i,.activations_i,.ready_o(ready[3]),.out_valid_o(valid[3]),.accumulations_o(result[3]));
  zero_dual_hold_systolic_npu_param dual(.clk,.rst_n,.clear_i,.load_weights_i,.weights_i,.in_valid_i,.activations_i,.ready_o(ready[4]),.out_valid_o(valid[4]),.accumulations_o(result[4]));
  function automatic logic [31:0] random_value;
    seed=32'd1664525*seed+32'd1013904223;
    return seed;
  endfunction
`ifndef PHY_NETLIST
  `include "isolation_monitors.svh"
`endif
  task automatic reset_all;
    @(negedge clk); measure=0;rst_n=0;clear_i=0;load_weights_i=0;in_valid_i=0;
    repeat(4) @(negedge clk);
    rst_n=1;
    for(int r=0;r<4;r++)expected[r]=0;
  endtask
  task automatic set_weights;
    @(negedge clk);load_weights_i=1;
    for(int j=0;j<16;j++) begin
      weights_i[j*8+:8]=8'(random_value());
      if(j%7==0)weights_i[j*8+:8]=0;
      if(j%7==1)weights_i[j*8+:8]=-128;
      if(j%7==2)weights_i[j*8+:8]=127;
    end
    @(negedge clk);load_weights_i=0;
  endtask
  task automatic launch_and_check;
    @(negedge clk);
    if(ready!==5'b11111)$fatal(1,"Ready mismatch");
    for(int r=0;r<4;r++) begin
      for(int c=0;c<4;c++)expected[r]+=$signed(weights_i[(r*4+c)*8+:8])*$signed(activations_i[c*8+:8]);
      expected[r]=$signed(24'(expected[r]));
    end
    in_valid_i=1;
    @(negedge clk);in_valid_i=0;elapsed=0;
    while(valid[0]!==1'b1) begin
      if(valid!==5'b00000)$fatal(1,"Completion schedule mismatch");
      if(elapsed>10)$fatal(1,"Job timeout");
      @(negedge clk);elapsed++;
    end
    if(valid!==5'b11111 || elapsed!=8)$fatal(1,"Latency mismatch %d",elapsed);
    if(elapsed<latency_min)latency_min=elapsed;
    if(elapsed>latency_max)latency_max=elapsed;
    for(int v=0;v<5;v++)for(int r=0;r<4;r++) begin
      if($signed(result[v][r*24+:24])!=expected[r])$fatal(1,"Variant=%d row=%d got=%d expected=%d",v,r,$signed(result[v][r*24+:24]),expected[r]);
      checks++;
    end
    jobs++;
  endtask
  initial begin
    integer ignored,percent,a;
    if($test$plusargs("CASE_0"))selected_case=0;
    if($test$plusargs("CASE_1"))selected_case=1;
    if($test$plusargs("CASE_2"))selected_case=2;
    if($test$plusargs("CASE_3"))selected_case=3;
    if($test$plusargs("CASE_4"))selected_case=4;
    if($test$plusargs("CASE_5"))selected_case=5;
    if($test$plusargs("CASE_6"))selected_case=6;
    if($test$plusargs("CASE_7"))selected_case=7;
    if($test$plusargs("CASE_DIRECTED"))selected_case=8;
    for(int k=0;k<8;k++)for(int v=0;v<5;v++)begin operand_toggles[k][v]=0;product_toggles[k][v]=0;end
    for(int profile=0;profile<2;profile++)for(int sp=0;sp<4;sp++)begin
      case_id=profile*4+sp;
      percent=sp==0?0:(sp==1?50:(sp==2?90:100));
      zeros=0;total_activations=0;
      if(selected_case<0 || selected_case==case_id)begin
        for(int corpus=0;corpus<4;corpus++)begin
          reset_all();
          seed=32'd20261028+32'(corpus*65537+case_id*8191);
          @(negedge clk);measure=1;
          if(profile==0)set_weights();
          for(int job=0;job<CORPUS_JOBS;job++)begin
            if(profile==1)set_weights();
            @(negedge clk);clear_i=1;
            @(negedge clk);clear_i=0;
            for(int r=0;r<4;r++)expected[r]=0;
            for(int c=0;c<4;c++)begin
              if(random_value()%100<percent)a=0;
              else begin
                a=$signed(8'(random_value()));
                if(job%16==0)a=-128;
                if(job%16==1)a=127;
              end
              activations_i[c*8+:8]=8'(a);
              total_activations++;
              if(a==0)zeros++;
            end
            launch_and_check();
            repeat(job%4)@(negedge clk);
          end
          @(negedge clk);measure=0;
        end
        for(int v=0;v<5;v++)begin
`ifndef PHY_NETLIST
          for(int r=0;r<4;r++)for(int c=0;c<4;c++)begin
            operand_toggles[case_id][v]+=pe_operand_toggles[v][r][c];
            product_toggles[case_id][v]+=pe_product_toggles[v][r][c];
          end
          if(case_id%4!=3 && operand_toggles[case_id][v]==0)$fatal(1,"Inactive switching instrumentation");
`endif
          $display("SWITCH,%0d,%0d,%0d,%0d,%0d,%0d,%0d",case_id,v,percent,zeros,total_activations,operand_toggles[case_id][v],product_toggles[case_id][v]);
        end
      end
    end
    if(selected_case<0 || selected_case==8)begin
      reset_all();seed=32'd617;
      set_weights();
      weights_i={16{8'h80}};
      @(negedge clk);load_weights_i=1;
      @(negedge clk);load_weights_i=0;
      activations_i={4{8'h80}};
      for(int job=0;job<OVERFLOW_JOBS;job++)launch_and_check();
      for(int operation=0;operation<2;operation++)begin
        @(negedge clk);in_valid_i=1;
        @(negedge clk);in_valid_i=0;
        repeat(2)@(negedge clk);
        if(operation==0)clear_i=1;else rst_n=0;
        @(negedge clk);clear_i=0;rst_n=1;
        repeat(12)begin
          @(negedge clk);
          if(valid!==0 || ready!==5'b11111)$fatal(1,"Abort control failure");
          for(int v=0;v<5;v++)if(result[v]!==0)$fatal(1,"Abort accumulator failure");
        end
      end
      reset_all();seed=32'd16391;set_weights();activations_i=32'h7f0080ff;launch_and_check();
    end
    $display("PASS isolation: jobs=%0d checked_rows_across_variants=%0d latency_min=%0d latency_max=%0d case=%0d",jobs,checks,latency_min,latency_max,selected_case);
    $finish;
  end
  initial begin
    #10000000;
    $fatal(1,"Isolation experiment timeout");
  end
endmodule
