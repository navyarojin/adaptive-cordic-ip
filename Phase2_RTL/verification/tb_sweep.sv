`timescale 1ns/1ps

module tb_controlled_eval #(parameter bit SHARED=1);
  import cordic_pkg::*;
  localparam int N=4,VECTORS=2048,WORKLOADS=6,WARMUP=256;
  logic clk=0,rst_n=0,valid_i=0;
  csr_to_ctrl_t csr_i;
  ctrl_to_csr_t status [0:N-1];
  logic [75:0] values_i;
  logic [15:0] tag_i;
  wire ready_o,valid_o,idle_o,reference_stall;
  wire [63:0] results;
  wire [15:0] result_tag;
  logic [18:0] inputs [0:WORKLOADS*VECTORS*N-1];
  integer cycle=0,accepted=0,retired=0,first_in,first_out,last_out,steady_first;
  integer input_stalls,ref_stalls,iterations_total,iterations_steady;
  integer case_id=0,output_file;
  bit measuring=0;
  always #20 clk=~clk;
  activation_stream_array #(.LANES(N),.TAG_WIDTH(16),.SHARED_REFERENCE(SHARED)) dut (
    .clk,.rst_n,.csr_i,.lane_status_o(status),.valid_i,.ready_o,.values_i,
    .rounding_i(1'b1),.tag_i,.valid_o,.ready_i(1'b1),.results_o(results),
    .tag_o(result_tag),.idle_o,.reference_stall_o(reference_stall));
  wire [4:0] selected [0:3];
  for(genvar l=0;l<4;l++) assign selected[l]=dut.lanes[l].unit.selected_iter_o;
  always @(posedge clk) begin
    cycle++;
    if(measuring && rst_n) begin
      if(valid_i && !ready_o) input_stalls++;
      if(valid_i && reference_stall) ref_stalls++;
      if(valid_i && ready_o) begin
        if(accepted==0) first_in=cycle;
        for(int l=0;l<N;l++) begin
          iterations_total+=selected[l];
          if(accepted>=WARMUP) iterations_steady+=selected[l];
        end
        accepted++;
      end
      if(valid_o) begin
        if(result_tag!=retired || retired>=accepted) $fatal(1,"Evaluation lost/reordered output");
        if(retired==0) first_out=cycle;
        if(retired==WARMUP) steady_first=cycle;
        last_out=cycle;
        for(int l=0;l<N;l++)
          $fdisplay(output_file,"%0d %0d %0d %0d",case_id,retired,l,$signed(results[l*16 +: 16]));
        retired++;
      end
    end
  end
  initial begin
    integer samples,fallbacks,max_residual;
    $readmemh("stimulus.mem",inputs);
    output_file=$fopen(SHARED ? "shared.raw" : "independent.raw","w");
    if(!output_file) $fatal(1,"Cannot open evaluation output");
    for(int mode=0;mode<2;mode++) for(int work=0;work<WORKLOADS;work++) for(int policy=0;policy<7;policy++) begin
      @(negedge clk); measuring=0; rst_n=0; valid_i=0;
      csr_i='0; csr_i.enable=1; csr_i.activation_mode=2'(mode);
      csr_i.min_iter=policy<2 ? 14 : 6; csr_i.max_iter=14; csr_i.full_iter=14;
      csr_i.sample_rate=(policy==1 || policy==2) ? 1 : ((policy==0 || policy==5) ? 0 : 32);
      csr_i.error_threshold=policy>=4 ? 8 : 0;
      csr_i.qualification_count=8; csr_i.violation_limit=3; csr_i.update_interval=32;
      csr_i.lut_freeze=policy<2 || policy==6;
      repeat(3) @(negedge clk);
      rst_n=1; accepted=0; retired=0; input_stalls=0; ref_stalls=0;
      iterations_total=0; iterations_steady=0; first_in=-1; first_out=-1; last_out=-1; steady_first=-1;
      case_id=mode*WORKLOADS*7+work*7+policy; measuring=1;
      for(int v=0;v<VECTORS;v++) begin
        @(negedge clk); valid_i=1; tag_i=16'(v);
        for(int l=0;l<N;l++) values_i[l*19 +: 19]=inputs[(work*VECTORS+v)*N+l];
        #1; while(!ready_o) begin @(negedge clk); #1; end
      end
      @(negedge clk); valid_i=0;
      wait(idle_o); @(negedge clk); measuring=0;
      if(accepted!=VECTORS || retired!=VECTORS) $fatal(1,"Evaluation count mismatch");
      samples=0; fallbacks=0; max_residual=0;
      for(int l=0;l<N;l++) begin
        samples+=status[l].sample_count; fallbacks+=status[l].fallback_count;
        if(status[l].max_error>max_residual) max_residual=status[l].max_error;
      end
      $display("EVAL,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",SHARED,case_id,mode,work,policy,
        first_out-first_in,last_out-first_in+1,last_out-steady_first+1,input_stalls,ref_stalls,
        iterations_total,iterations_steady,samples,fallbacks,max_residual);
    end
    $fclose(output_file);
    $display("PASS controlled evaluation shared=%0d cases=84",SHARED);
    $finish;
  end
  initial begin #200000000; $fatal(1,"Evaluation timeout"); end
endmodule
module tb_eval_shared;
  tb_controlled_eval #(.SHARED(1)) test();
endmodule
module tb_eval_independent;
  tb_controlled_eval #(.SHARED(0)) test();
endmodule
