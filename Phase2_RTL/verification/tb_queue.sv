`timescale 1ns/1ps
module queue_case #(parameter int DEPTH=4)(output bit done=0);
  bit clk=0,rst_n=0,push_valid=0,pop_ready=0;
  logic push_ready,pop_valid;
  logic [31:0] push_data=0,pop_data;
  logic [$clog2(DEPTH+1)-1:0] count;
  int unsigned expected[$];
  int unsigned seed=32'h153897ab;
  int checks=0;
  always #5 clk=~clk;
  hardware_command_queue #(.DEPTH(DEPTH)) dut(clk,rst_n,push_valid,push_ready,push_data,pop_valid,pop_ready,pop_data,count);
  task automatic step(input bit reset_value,push_value,pop_value);
    bit take_push,take_pop;
    int unsigned discarded;
    @(negedge clk);
    rst_n=reset_value; push_valid=push_value; pop_ready=pop_value;
    seed=1664525*seed+1013904223;
    push_data=seed;
    #1;
    if (pop_valid !== (reset_value && expected.size()!=0)) $fatal(1,"Queue valid depth %0d",DEPTH);
    take_pop=pop_valid && pop_ready;
    if (push_ready !== (reset_value && (expected.size()<DEPTH || take_pop))) $fatal(1,"Queue ready depth %0d",DEPTH);
    take_push=push_ready && push_valid;
    if (take_pop) begin
      discarded=expected.pop_front();
      if (pop_data!==discarded) $fatal(1,"Queue order depth %0d",DEPTH);
      checks++;
    end
    if (take_push) expected.push_back(push_data);
    if (!reset_value) expected.delete();
    @(posedge clk); #1;
    if (int'(count)!=expected.size()) $fatal(1,"Queue occupancy depth %0d",DEPTH);
  endtask
  initial begin
    step(0,0,0);
    repeat(DEPTH+2) step(1,1,0);
    repeat(4*DEPTH) step(1,1,1);
    repeat(DEPTH+2) step(1,0,1);
    for (int i=0;i<4096;i++) step(i%257!=0,seed[29],seed[17]);
    repeat(DEPTH+2) step(1,0,1);
    step(0,1,1);
    $display("PASS command queue depth=%0d ordered transfers=%0d",DEPTH,checks);
    done=1;
  end
endmodule
module tb_command_queue;
  wire [2:0] done;
  queue_case #(1) q1(done[0]);
  queue_case #(3) q3(done[1]);
  queue_case #(4) q4(done[2]);
  initial begin wait(&done); $finish; end
  initial begin #100000; $fatal(1,"Queue timeout"); end
endmodule
