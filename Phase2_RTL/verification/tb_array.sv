`timescale 1ns/1ps
module tb_activation_stream_array;
  wire reference_stall_o;
  import cordic_pkg::*;
  import activation_reference_pkg::*;
  parameter int ACTIVATION_LANES=4;
  localparam int N=ACTIVATION_LANES;
  logic clk=0,rst_n=0,valid_i=0,ready_i=1,rounding_i=1;
  csr_to_ctrl_t csr_i;
  ctrl_to_csr_t lane_status_o [0:N-1];
  logic [N*19-1:0] values_i;
  logic [15:0] tag_i;
  wire valid_o,ready_o,idle_o;
  wire [N*16-1:0] results_o;
  wire [15:0] tag_o;
  integer expected [0:4095][0:N-1];
  integer sent=0,received=0;
  integer checks=0;
  always #5 clk=~clk;
  parameter bit SHARED_REFERENCE=1;
  activation_stream_array #(.LANES(N),.TAG_WIDTH(16),.SHARED_REFERENCE(SHARED_REFERENCE)) dut (.*);
  always @(posedge clk) begin
    if (rst_n) begin
      if (valid_i && ready_o) begin
        for (int l=0;l<N;l++)
          expected[sent][l]=activation_fixed(int'($signed(values_i[l*19 +: 19])),int'(csr_i.activation_mode),14,1);
        sent++;
      end
      if (valid_o && ready_i) begin
        if (received>=sent || tag_o!=16'(received)) $fatal(1,"Array ordering error");
        for (int l=0;l<N;l++) begin
          if (int'($signed(results_o[l*16 +: 16]))!=expected[received][l])
            $fatal(1,"Array N=%0d vector=%0d lane=%0d result=%0d expected=%0d",N,received,l,$signed(results_o[l*16 +: 16]),expected[received][l]);
          checks++;
        end
        received++;
      end
    end
  end
  initial begin
    csr_i='0;
    csr_i.enable=1;
    csr_i.min_iter=6;
    csr_i.max_iter=14;
    csr_i.full_iter=14;
    csr_i.sample_rate=1;
    csr_i.error_threshold=0;
    csr_i.qualification_count=2;
    csr_i.violation_limit=3;
    repeat(3) @(negedge clk); rst_n=1;
    for (int mode=0;mode<4;mode++) begin
      csr_i.activation_mode=2'(mode);
      for (int i=0;i<512;i++) begin
        @(negedge clk);
        valid_i=1;
        tag_i=16'(sent);
        for (int l=0;l<N;l++) values_i[l*19 +: 19]=19'(((i*811+l*9739)%131073)-65536);
        ready_i=i%11!=0;
        #1;
        if (!ready_o) begin @(negedge clk); ready_i=1; #1; end
        while (!ready_o) @(negedge clk);
      end
      @(negedge clk); valid_i=0; ready_i=1;
      wait(idle_o);
      @(negedge clk);
      if (received!=sent) $fatal(1,"Array did not drain");
    end
    for (int l=0;l<N;l++) begin
      if (lane_status_o[l].sample_count!=1024) $fatal(1,"Sampling count lane=%0d count=%0d",l,lane_status_o[l].sample_count);
      if (lane_status_o[l].fallback_count==0 || !lane_status_o[l].fallback_flag)
        $fatal(1,"Fallback not exercised lane=%0d",l);
    end
    csr_i.lut_reset=1;
    @(negedge clk); csr_i.lut_reset=0;
    for (int l=0;l<N;l++)
      if (lane_status_o[l].fallback_flag || lane_status_o[l].sample_count!=1024)
        $fatal(1,"Learning reset lifetime counter semantics");
    $display("PASS adaptive streaming array lanes=%0d checks=%0d sampling/fallback/reset",N,checks);
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1,"Adaptive streaming array timeout");
  end
endmodule
