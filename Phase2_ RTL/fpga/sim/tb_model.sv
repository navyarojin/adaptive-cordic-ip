`timescale 1ns/1ps
module tb_banknote_model;
  import cordic_pkg::*;
  logic clk=0,rst_n=0,command_valid_i=0,command_bank_i=0;
  logic [6:0] command_count_i;
  logic [15:0] command_tag_i;
  csr_to_ctrl_t command_cfg_i;
  logic command_fused_i=1;
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
  stream_job_engine #(.LANES(4),.SHARED_REFERENCE(1)) dut(.command_model_i(1'b0),.command_weights2_i(128'b0),.command_bias2_i(128'b0),.*);
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
    end
    command_count_i=7'(count); command_tag_i=16'(tag); command_valid_i=1;
    #1; while(!command_ready_o) begin @(negedge clk); #1; end
    @(negedge clk); command_valid_i=0;
    if(command_rejected_o) $fatal(1,"Model command rejected");
    wait(done_o[0]); @(negedge clk);
    if(completed_tag_o[0]!=tag || performance_o[0][3]!=count || performance_o[0][4]!=count)
      $fatal(1,"Model job tag/count mismatch");
    kernel_cycles+=performance_o[0][2]+1;
  endtask
  task automatic release_bank;
    @(negedge clk); release_i=1;
    @(negedge clk); release_i=0;
    if(locked_o[0]) $fatal(1,"Model release failed");
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
    $readmemh("model.mem",model);
    samples=model[0];
    if(samples<1 || samples>1372) $fatal(1,"Invalid model test count");
    $readmemh("inputs.mem",inputs,0,samples*4-1);
    output_file=$fopen("model.raw","w");
    if(!output_file) $fatal(1,"Cannot write model output");
    for(int policy=0;policy<7;policy++) begin
      @(negedge clk); rst_n=0;
      command_cfg_i='0; command_cfg_i.enable=1;
      command_cfg_i.min_iter=policy<2 ? 14 : 6; command_cfg_i.max_iter=14; command_cfg_i.full_iter=14;
      command_cfg_i.sample_rate=(policy==1 || policy==2) ? 1 : ((policy==0 || policy==5) ? 0 : 32);
      command_cfg_i.error_threshold=policy>=4 ? 8 : 0;
      command_cfg_i.qualification_count=8; command_cfg_i.violation_limit=3; command_cfg_i.update_interval=32;
      command_cfg_i.lut_freeze=policy<2 || policy==6;
      repeat(3) @(negedge clk); rst_n=1; kernel_cycles=0;
      for(int base=0;base<samples;base+=64) begin
        count=samples-base<64 ? samples-base : 64;
        for(int v=0;v<count;v++) for(int l=0;l<4;l++) write_input(v,l,$signed(inputs[(base+v)*4+l]));
        submit(0,count,policy*100+base/32);
        for(int v=0;v<count;v++) for(int l=0;l<4;l++) begin
          read_output(v,l,value); hidden[v*4+l]=requant(value);
        end
        release_bank();
        for(int v=0;v<count;v++) for(int l=0;l<4;l++) write_input(v,l,hidden[v*4+l]);
        submit(1,count,policy*100+base/32+1);
        for(int v=0;v<count;v++) begin
          read_output(v,0,value); $fdisplay(output_file,"%0d %0d %0d",policy,base+v,value);
        end
        release_bank();
      end
      $display("MODEL_CYCLES,%0d,%0d",policy,kernel_cycles);
    end
    $fclose(output_file);
    $display("PASS banknote model: %0d held-out samples x 7 policies; real fused RTL; host inter-layer requantization",samples);
    $finish;
  end
  initial begin #20000000; $fatal(1,"Model evaluation timeout"); end
endmodule
