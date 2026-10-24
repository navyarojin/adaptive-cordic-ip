`timescale 1ns/1ps
module tb_autonomous_model;
  import cordic_pkg::*;
  logic clk=0,rst_n=0,command_valid_i=0,command_bank_i=0;
  logic [6:0] command_count_i;
  logic [15:0] command_tag_i;
  csr_to_ctrl_t command_cfg_i;
  logic command_fused_i=1;
  logic command_model_i=1;
  logic [127:0] command_weights2_i,command_bias2_i;
  logic [31:0] expected_mem[0:270];
  logic [127:0] command_weights_i,command_bias_i;
  logic [4:0] command_shift_i=0;
  wire command_ready_o,command_rejected_o;
  logic release_i=0,release_bank_i=0;
  wire [1:0] locked_o,done_o;
  wire [15:0] completed_tag_o[0:1];
  wire irq_o;
  logic host_write_i=0,host_read_i=0,host_bank_i=0;
  logic [1:0] host_lane_i;
  logic [5:0] host_index_i;
  logic [3:0] host_be_i=15;
  logic [31:0] host_wdata_i;
  wire [31:0] host_rdata_o;
  wire host_rejected_o;
  ctrl_to_csr_t lane_status_o[0:3];
  wire [31:0] performance_o[0:1][0:6];
  logic [31:0] model[0:16],inputs[0:5487];
  integer hidden[0:255],samples,output_file,kernel_cycles;
  always #20 clk=~clk;
  stream_job_engine #(.LANES(4),.SHARED_REFERENCE(1)) dut(.*);
  task automatic write_input(input int vector_index,lane,value);
    @(negedge clk); host_write_i=1; host_index_i=6'(vector_index); host_lane_i=2'(lane); host_wdata_i=32'(value);
    @(negedge clk); host_write_i=0;
  endtask
  task automatic read_output(input int vector_index,lane,output int value);
    @(negedge clk); host_read_i=1; host_index_i=6'(vector_index); host_lane_i=2'(lane);
    @(negedge clk); value=$signed(host_rdata_o); host_read_i=0;
  endtask
  task automatic submit(input int layer,count,tag);
    @(negedge clk); command_cfg_i.activation_mode=2'(layer);
    for(int r=0;r<4;r++) begin
      command_weights_i[r*32 +: 32]=model[1+8*layer+r];
      command_bias_i[r*32 +: 32]=model[5+8*layer+r];
      command_weights2_i[r*32 +: 32]=model[9+r];
      command_bias2_i[r*32 +: 32]=model[13+r];
    end
    command_count_i=7'(count); command_tag_i=16'(tag); command_valid_i=1;
    #1; while(!command_ready_o) begin @(negedge clk); #1; end
    @(negedge clk); command_valid_i=0;
    if(command_rejected_o) $fatal(1,"Model command rejected");
    command_weights_i=0; command_bias_i=0; command_weights2_i=0; command_bias2_i=0;
    wait(done_o[command_bank_i]); @(negedge clk);
    if(completed_tag_o[command_bank_i]!=tag || performance_o[command_bank_i][3]!=count || performance_o[command_bank_i][4]!=count)
      $fatal(1,"Model job tag/count mismatch");
    kernel_cycles+=performance_o[command_bank_i][2]+1;
  endtask
  task automatic release_bank;
    @(negedge clk); release_i=1;
    @(negedge clk); release_i=0;
    if(locked_o[command_bank_i]) $fatal(1,"Model release failed");
  endtask
  function automatic int requant(input int value);
    int magnitude,result;
    magnitude=value<0 ? -value : value;
    result=(magnitude+64)/128;
    if(value<0) result=-result;
    if(result>127) result=127;
    if(result< -128) result=-128;
    return result;
  endfunction
  initial begin
    integer count,value;
    for(int raw=-32768;raw<=32767;raw++)
      if($signed(dut.requant(16'(raw)))!=requant(raw)) $fatal(1,"Requant rounding mismatch %0d",raw);
    $readmemh("model.mem",model);
    $readmemh("gold.mem",expected_mem);
    samples=model[0];
    if(samples<1 || samples>1372) $fatal(1,"Invalid model test count");
    $readmemh("inputs.mem",inputs,0,samples*4-1);
    output_file=$fopen("autonomous.raw","w");
    if(!output_file) $fatal(1,"Cannot write model output");
    for(int policy=0;policy<1;policy++) begin
      @(negedge clk); rst_n=0;
      command_cfg_i='0; command_cfg_i.enable=1;
      command_cfg_i.min_iter=policy<2 ? 14 : 6; command_cfg_i.max_iter=14; command_cfg_i.full_iter=14;
      command_cfg_i.sample_rate=(policy==1 || policy==2) ? 1 : ((policy==0 || policy==5) ? 0 : 32);
      command_cfg_i.error_threshold=policy>=4 ? 8 : 0;
      command_cfg_i.qualification_count=8; command_cfg_i.violation_limit=3; command_cfg_i.update_interval=32;
      command_cfg_i.lut_freeze=policy<2 || policy==6;
      repeat(3) @(negedge clk); rst_n=1; kernel_cycles=0;

      for(int b=0;b<2;b++) begin
        host_bank_i=1'(b);
        for(int v=0;v<2;v++) for(int l=0;l<4;l++) write_input(v,l,$signed(inputs[v*4+l]));
      end
      for(int b=0;b<2;b++) begin
        @(negedge clk); command_bank_i=1'(b); command_count_i=2; command_tag_i=16'(900+b);
        for(int r=0;r<4;r++) begin
          command_weights_i[r*32 +: 32]=model[1+r]; command_bias_i[r*32 +: 32]=model[5+r];
          command_weights2_i[r*32 +: 32]=model[9+r]; command_bias2_i[r*32 +: 32]=model[13+r];
        end
        command_valid_i=1;
        @(negedge clk); command_valid_i=0;
        if(command_rejected_o) $fatal(1,"Queued model rejected");
      end
      command_weights_i=0; command_weights2_i=0; command_bias_i=0; command_bias2_i=0;
      wait(done_o==2'b11);
      for(int b=0;b<2;b++) begin
        host_bank_i=1'(b); command_bank_i=1'(b); release_bank_i=1'(b);
        if(completed_tag_o[b]!=900+b) $fatal(1,"Queued model tag");
        for(int v=0;v<2;v++) begin
          read_output(v,0,value); if(value!=$signed(expected_mem[v])) $fatal(1,"Queued model snapshot");
        end
        release_bank();
      end
      for(int base=0;base<samples;) begin
        count=base==0 ? 1 : (base==1 ? 2 : (samples-base<64 ? samples-base : 64));
        command_bank_i=~command_bank_i; host_bank_i=command_bank_i; release_bank_i=command_bank_i;
        for(int v=0;v<count;v++) for(int l=0;l<4;l++) write_input(v,l,$signed(inputs[(base+v)*4+l]));
        submit(0,count,base+1);
        for(int v=0;v<count;v++) begin
          read_output(v,0,value);
          if(value!=$signed(expected_mem[base+v])) $fatal(1,"Autonomous mismatch row %0d got %0d expected %0d",base+v,value,$signed(expected_mem[base+v]));
          $fdisplay(output_file,"%0d %0d",base+v,value);
        end
        release_bank();
        base+=count;
      end
      $display("MODEL_CYCLES,%0d,%0d",policy,kernel_cycles);
    end

    for(int phase=0;phase<2;phase++) begin
      @(negedge clk); command_bank_i=0; command_count_i=1; command_valid_i=1;
      @(negedge clk); command_valid_i=0;
      if(phase==1) wait(dut.second_layer);
      else repeat(10) @(negedge clk);
      @(negedge clk); rst_n=0;
      repeat(3) @(negedge clk);
      rst_n=1;
      repeat(250) @(negedge clk);
      if(done_o || locked_o || irq_o) $fatal(1,"Stale model completion after reset");
    end
    $fclose(output_file);
    $display("PASS autonomous model: %0d exact fixed14 results; single-command; alternating banks; 1/2/64/partial batches; captured weights",samples);
    $finish;
  end
  initial begin #20000000; $fatal(1,"Model evaluation timeout"); end
endmodule
