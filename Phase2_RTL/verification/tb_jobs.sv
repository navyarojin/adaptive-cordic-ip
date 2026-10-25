`timescale 1ns/1ps
module tb_stream_job_engine;
  import cordic_pkg::*;
  parameter int ACTIVATION_LANES=4;
  localparam int N=ACTIVATION_LANES;
  logic clk=0,rst_n=0,command_valid_i=0,command_bank_i=0;
  logic [6:0] command_count_i=8;
  logic [15:0] command_tag_i;
  csr_to_ctrl_t command_cfg_i;
  wire command_ready_o,command_rejected_o;
  logic release_i=0,release_bank_i=0;
  wire [1:0] locked_o,done_o;
  wire [15:0] completed_tag_o [0:1];
  wire irq_o;
  logic host_write_i=0,host_read_i=0,host_bank_i=0;
  logic [(N<=1 ? 1:$clog2(N))-1:0] host_lane_i;
  logic [5:0] host_index_i;
  logic [3:0] host_be_i=15;
  logic [31:0] host_wdata_i;
  wire [31:0] host_rdata_o;
  wire host_rejected_o;
  ctrl_to_csr_t lane_status_o [0:N-1];
  logic command_fused_i=0;
  logic [127:0] command_weights_i=0,command_bias_i=0;
  logic [4:0] command_shift_i=0;
  wire [31:0] performance_o [0:1][0:6];
  integer expected [0:1][0:7][0:N-1];
  integer checks=0;
  always #5 clk=~clk;
  stream_job_engine #(.LANES(N)) dut (.command_model_i(1'b0),.command_weights2_i(128'b0),.command_bias2_i(128'b0),.*);
  task automatic submit(input bit bank,input int count,input int tag,input bit reject);
    @(negedge clk);
    command_bank_i=bank; command_count_i=7'(count); command_tag_i=16'(tag);
    command_valid_i=1;
    while (!command_ready_o) @(negedge clk);
    @(negedge clk); command_valid_i=0;
    if (command_rejected_o!=reject) $fatal(1,"Command rejection mismatch");
  endtask
  initial begin
    command_cfg_i='0;
    command_cfg_i.enable=1;
    command_cfg_i.min_iter=14;
    command_cfg_i.max_iter=14;
    command_cfg_i.full_iter=14;
    command_cfg_i.activation_mode=3;
    repeat(3) @(negedge clk); rst_n=1;
    submit(0,0,0,1);
    if (N!=4) begin
      command_fused_i=1; submit(0,8,0,1); command_fused_i=0;
    end
    for (int b=0;b<2;b++) begin
      for (int i=0;i<8;i++) begin
        for (int l=0;l<N;l++) begin
          @(negedge clk);
          host_write_i=1; host_bank_i=1'(b); host_index_i=6'(i); host_lane_i=l;
          host_wdata_i=32'(i*7+l-16);
          expected[b][i][l]=i*7+l-16;
        end
      end
      @(negedge clk); host_write_i=0;
      if (b==1) begin
        @(negedge clk); host_write_i=1; host_index_i=0; host_lane_i=0;
        host_be_i=1; host_wdata_i=32'h000000a5;
        @(negedge clk); host_write_i=0; host_be_i=15;
        expected[b][0][0]=-91;
      end
      submit(1'(b),8,32'haa00+b,0);
      submit(1'(b),8,0,1);
      @(negedge clk); host_write_i=1;
      #1;
      if (!host_rejected_o) $fatal(1,"Locked buffer accepted host write");
      @(negedge clk); host_write_i=0;
    end
    wait(&done_o);
    @(negedge clk);
    if (!irq_o || locked_o!=3 || completed_tag_o[0]!=16'haa00 || completed_tag_o[1]!=16'haa01)
      $fatal(1,"Completion/ownership mismatch");
    for (int b=0;b<2;b++) begin
      for (int i=0;i<8;i++) begin
        for (int l=0;l<N;l++) begin
          @(negedge clk);
          host_read_i=1; host_bank_i=1'(b); host_index_i=6'(i); host_lane_i=l;
          @(negedge clk);
          if ($signed(host_rdata_o)!=expected[b][i][l])
            $fatal(1,"Buffer bank=%0d vector=%0d lane=%0d got=%0d expected=%0d",b,i,l,$signed(host_rdata_o),expected[b][i][l]);
          checks++;
        end
      end
      host_read_i=0; release_i=1; release_bank_i=1'(b);
      @(negedge clk); release_i=0;
    end
    if (irq_o || locked_o!=0) $fatal(1,"Release failed");
    submit(0,8,5,0);
    repeat(20) @(negedge clk);
    rst_n=0;
    repeat(2) @(negedge clk); rst_n=1;
    repeat(150) @(negedge clk);
    if (irq_o || locked_o!=0 || done_o!=0) $fatal(1,"Reset ownership flush failed");
    $display("PASS stream job engine: checks=%0d queued jobs, ping-pong overlap, ownership, invalid commands, IRQ, reset",checks);
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1,"Stream job engine timeout");
  end
endmodule
