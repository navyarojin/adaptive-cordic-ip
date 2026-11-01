`timescale 1ns/1ps
module tb_stream_throughput;
  import cordic_pkg::*;
  parameter int ACTIVATION_LANES=4;
  localparam int N=ACTIVATION_LANES;
  logic clk=0,rst_n=0,valid_i=0;
  logic bench_reset=1;
  csr_to_ctrl_t csr_i;
  ctrl_to_csr_t lane_status_o [0:N-1];
  logic [N*19-1:0] values_i;
  logic [15:0] tag_i;
  wire ready_o,valid_o,idle_o;
  wire [N*16-1:0] results_o;
  wire [15:0] tag_o;
  integer cycle=0,accepted=0,retired=0;
  integer first_input=-1,first_output=-1,last_output=-1;
  always #20 clk=~clk;
  activation_stream_array #(.LANES(N),.TAG_WIDTH(16),.SHARED_REFERENCE(1)) dut (
    .clk,.rst_n,.csr_i,.lane_status_o,.valid_i,.ready_o,.values_i,.rounding_i(1'b1),
    .tag_i,.valid_o,.ready_i(1'b1),.results_o,.tag_o,.idle_o);
  always @(posedge clk) begin
    cycle++;
    if (bench_reset) begin
      accepted=0; retired=0; first_input=-1; first_output=-1; last_output=-1;
    end else begin
    if (rst_n && valid_i && ready_o) begin
      if (first_input<0) first_input=cycle;
      accepted++;
    end
    if (rst_n && valid_o) begin
      if (tag_o!=16'(retired)) $fatal(1,"Throughput output ordering");
      if (first_output<0) first_output=cycle;
      last_output=cycle;
      retired++;
    end
    end
  end
  initial begin
    csr_i='0; csr_i.enable=1; csr_i.min_iter=6; csr_i.max_iter=14; csr_i.full_iter=14;
    csr_i.error_threshold=0; csr_i.qualification_count=8; csr_i.violation_limit=3;
    repeat(3) @(negedge clk); rst_n=1;
    for (int phase=0;phase<3;phase++) begin
      @(negedge clk);
      csr_i.lut_reset=1;
      bench_reset=1;
      @(negedge clk); csr_i.lut_reset=0;
      csr_i.sample_rate=phase==0 ? 0 : (phase==1 ? 32 : 1);
      bench_reset=0;
      for (int vector_index=0;vector_index<2048;vector_index++) begin
        @(negedge clk);
        valid_i=1; tag_i=16'(vector_index);
        for (int lane=0;lane<N;lane++) values_i[lane*19 +: 19]=19'(((vector_index*811+lane*979)%131073)-65536);
        #1;
        while (!ready_o) begin @(negedge clk); #1; end
      end
      @(negedge clk); valid_i=0;
      wait(idle_o);
      @(negedge clk);
      if (accepted!=2048 || retired!=2048) $fatal(1,"Throughput transaction count");
      if (first_input<0 || first_output<first_input || last_output<first_output)
        $fatal(1,"Invalid throughput timestamps %0d %0d %0d",first_input,first_output,last_output);
      $display("STREAM_THROUGHPUT,%0d,%0d,%0d,%0d,%0d,%0d",N,csr_i.sample_rate,retired,first_output-first_input,last_output-first_output+1,last_output-first_input+1);
    end
    $finish;
  end
  initial begin #2000000; $fatal(1,"Throughput timeout"); end
endmodule
