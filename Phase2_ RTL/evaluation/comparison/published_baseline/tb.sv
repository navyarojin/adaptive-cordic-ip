`timescale 1ns/1ps
module tb_published_comparison;
  logic clk=0,rst_n=0,valid_i=0;
  logic signed [15:0] x_i;
  wire baseline_valid,cordic_valid;
  wire signed [15:0] baseline_y,cordic_y;
  integer baseline_count=0,cordic_count=0;
  integer cycle=0,first_input=-1,baseline_latency=-1,cordic_latency=-1;
  integer baseline_previous=-1,cordic_previous=-1;
  real baseline_abs=0,baseline_sq=0,baseline_max=0;
  real cordic_abs=0,cordic_sq=0,cordic_max=0;
  real x,reference_value,error_value,absolute_error;
  integer fd;
  always #20 clk=~clk;
  published_sigmoid_benchmark baseline(.clk,.rst_n,.valid_i,.x_i,.valid_o(baseline_valid),.y_o(baseline_y));
  cordic_sigmoid_benchmark ours(.clk,.rst_n,.valid_i,.x_i,.valid_o(cordic_valid),.y_o(cordic_y));
  always @(posedge clk) begin
    cycle++;
    if (rst_n && valid_i && first_input<0) first_input=cycle;
    #1;
    if (baseline_valid) begin
      if (baseline_previous>=0 && cycle!=baseline_previous+1) $fatal(1,"Baseline II mismatch");
      if (baseline_latency<0) baseline_latency=cycle-first_input+1;
      baseline_previous=cycle;
      x=real'(baseline_count-32768)/4096.0;
      reference_value=1.0/(1.0+$exp(-x));
      error_value=real'($signed(baseline_y))/4096.0-reference_value;
      absolute_error=error_value<0 ? -error_value:error_value;
      baseline_abs+=absolute_error; baseline_sq+=error_value*error_value;
      if (absolute_error>baseline_max) baseline_max=absolute_error;
      baseline_count++;
    end
    if (cordic_valid) begin
      if (cordic_previous>=0 && cycle!=cordic_previous+1) $fatal(1,"CORDIC II mismatch");
      if (cordic_latency<0) cordic_latency=cycle-first_input+1;
      cordic_previous=cycle;
      x=real'(cordic_count-32768)/4096.0;
      reference_value=1.0/(1.0+$exp(-x));
      error_value=real'($signed(cordic_y))/4096.0-reference_value;
      absolute_error=error_value<0 ? -error_value:error_value;
      cordic_abs+=absolute_error; cordic_sq+=error_value*error_value;
      if (absolute_error>cordic_max) cordic_max=absolute_error;
      cordic_count++;
    end
  end
  initial begin
    repeat(3) @(negedge clk); rst_n=1;
    for (int value=-32768;value<32768;value++) begin
      @(negedge clk); valid_i=1; x_i=16'(value);
    end
    @(negedge clk); valid_i=0;
    wait(cordic_count==65536);
    @(negedge clk);
    if (baseline_count!=65536) $fatal(1,"Baseline missing results");
    fd=$fopen("published_accuracy.csv","w");
    $fdisplay(fd,"design,samples,input_format,output_format,min_input,max_input,clock_mhz,latency_clocks,ii,mae,rmse,max_error");
    $fdisplay(fd,"Bosso2025,65536,Q4.12,Q4.12,-8,7.999755859375,25,%0d,1,%.12f,%.12f,%.12f",baseline_latency,baseline_abs/65536,$sqrt(baseline_sq/65536),baseline_max);
    $fdisplay(fd,"CORDIC_Q14_internal,65536,Q4.12,Q4.12,-8,7.999755859375,25,%0d,1,%.12f,%.12f,%.12f",cordic_latency,cordic_abs/65536,$sqrt(cordic_sq/65536),cordic_max);
    $fclose(fd);
    $display("PASS published comparison: 65536 inputs each, baseline latency=%0d CORDIC latency=%0d II=1 at 25 MHz",baseline_latency,cordic_latency);
    $finish;
  end
  initial begin
    #3000000;
    $fatal(1,"Published comparison timeout");
  end
endmodule
