`timescale 1ns/1ps
module tb_cordic_stream;
  import activation_reference_pkg::*;
  logic clk=0,rst_n=0,valid_i=0,ready_i=1;
  logic signed [18:0] value_i;
  logic [1:0] mode_i;
  logic [4:0] iterations_i;
  logic rounding_i;
  logic [15:0] tag_i;
  wire valid_o,ready_o;
  wire signed [15:0] result_o;
  wire [15:0] tag_o;
  integer expected [0:16383];
  integer tags [0:16383];
  integer accepted_cycle [0:16383];
  integer sent=0,received=0,cycle=0;
  integer first_latency=-1,last_output=-1;
  bit continuous=1;
  logic stalled=0;
  logic [31:0] held;
  always #5 clk=~clk;
  cordic_activation_stream #(.TAG_WIDTH(16)) dut (.*);
  always @(posedge clk) begin
    cycle++;
    if (!rst_n) begin sent=0; received=0; stalled=0; end
    else begin
      if (stalled && (!valid_o || {result_o,tag_o}!==held))
        $fatal(1,"CORDIC output changed while stalled");
      stalled=valid_o && !ready_i;
      held={result_o,tag_o};
      if (valid_i && ready_o) begin
        expected[sent]=activation_fixed(int'($signed(value_i)),int'(mode_i),int'(iterations_i),int'(rounding_i));
        tags[sent]=tag_i;
        accepted_cycle[sent]=cycle;
        sent++;
      end
      if (valid_o && ready_i) begin
        if (received>=sent) $fatal(1,"Unexpected CORDIC result");
        if (int'($signed(result_o))!=expected[received] || tag_o!=tags[received])
          $fatal(1,"CORDIC index=%0d got=%0d expected=%0d tag=%0d",received,$signed(result_o),expected[received],tag_o);
        if (continuous) begin
          if (first_latency<0) first_latency=cycle-accepted_cycle[received];
          if (cycle-accepted_cycle[received]!=first_latency) $fatal(1,"Variable streaming latency");
          if (last_output>=0 && cycle!=last_output+1) $fatal(1,"Streaming initiation interval is not one");
          last_output=cycle;
        end
        received++;
      end
    end
  end
  task automatic send_batch(input bit stalls);
    for (int i=0;i<8192;i++) begin
      @(negedge clk);
      value_i=19'(((i*811)%524288)-262144);
      if (i%16==0) value_i=0;
      if (i%16==1) value_i=85197;
      if (i%16==2) value_i=-85197;
      mode_i=2'(i%4);
      iterations_i=5'(6+(i/4)%11);
      rounding_i=1'(i/44);
      tag_i=16'(i);
      valid_i=1;
      ready_i=!stalls || i%9!=0;
      #1;
      if (!ready_o) begin
        @(negedge clk); ready_i=1; #1;
      end
      while (!ready_o) @(negedge clk);
    end
    @(negedge clk); valid_i=0; ready_i=1;
    wait(received==sent);
    repeat(2) @(negedge clk);
  endtask
  initial begin
    repeat(3) @(negedge clk); rst_n=1;
    send_batch(0);
    if (received!=8192) $fatal(1,"Missing continuous results");
    continuous=0;
    send_batch(1);
    if (received!=16384) $fatal(1,"Missing stalled results");
    $display("PASS streaming CORDIC: %0d exact reference checks, latency=%0d clocks, II=1, backpressure",received,first_latency);
    @(negedge clk); rst_n=0;
    repeat(2) @(negedge clk); rst_n=1; valid_i=1;
    repeat(40) @(negedge clk);
    rst_n=0; valid_i=0;
    repeat(2) @(negedge clk); rst_n=1;
    repeat(200) begin
      @(negedge clk);
      if (valid_o) $fatal(1,"CORDIC reset failed to flush");
    end
    $display("PASS streaming CORDIC reset during active pipeline");
    $finish;
  end
  initial begin
    #2000000;
    $fatal(1,"Streaming CORDIC timeout");
  end
endmodule
