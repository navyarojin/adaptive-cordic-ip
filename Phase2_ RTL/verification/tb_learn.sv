`timescale 1ns/1ps
module tb_stream_learning;
  import cordic_pkg::*;
  logic clk=0,rst_n=0,launch=0;
  logic signed [18:0] value;
  csr_to_ctrl_t cfg;
  ctrl_to_csr_t legacy_status,stream_status;
  ctrl_to_core_t request;
  core_to_ctrl_t response;
  wire legacy_valid,stream_valid,stream_ready;
  wire signed [15:0] legacy_result,stream_result;
  logic legacy_seen=0,stream_seen=0;
  logic signed [15:0] saved_legacy,saved_stream;
  integer checks=0;
  integer samples_before;
  always #5 clk=~clk;
  qualification_ctrl legacy (
    .clk,.rst_n,.x_valid_i(launch),.x_i(value),.core_ctrl_o(request),.core_ctrl_i(response),
    .csr_i(cfg),.csr_o(legacy_status),.result_valid_o(legacy_valid),.result_o(legacy_result));
  cordic_core legacy_core (
    .clk,.rst_n,.ctrl_i(request),.full_iter_i(bounded_full_iter(cfg.full_iter,cfg.min_iter)),
    .round_mode_en_i(1'b1),.ctrl_o(response),.dbg_valid_o(),.dbg_full_result_o(),.dbg_overflow_o());
  qualification_stream streaming (
    .clk,.rst_n,.csr_i(cfg),.csr_o(stream_status),.valid_i(launch),.ready_o(stream_ready),
    .value_i(value),.rounding_i(1'b1),.tag_i(1'b0),.valid_o(stream_valid),.ready_i(1'b1),
    .result_o(stream_result),.tag_o(),.idle_o(),.selected_iter_o(),.sample_o(),
    .reference_valid_i(1'b0),.reference_result_i(16'sd0),.reference_ready_o());
  always @(negedge clk) begin
    if (legacy_valid) begin saved_legacy=legacy_result; legacy_seen=1; end
    if (stream_valid) begin saved_stream=stream_result; stream_seen=1; end
  end
  initial begin
    cfg='0; cfg.enable=1; cfg.min_iter=6; cfg.max_iter=14; cfg.full_iter=14;
    cfg.sample_rate=1; cfg.qualification_count=3; cfg.violation_limit=2;
    repeat(3) @(negedge clk); rst_n=1;
    for (int phase=0;phase<10;phase++) begin
      @(negedge clk);
      cfg.lut_reset=phase!=9;
      @(negedge clk); cfg.lut_reset=0;
      cfg.activation_mode=2'(phase<4 ? phase : phase%2);
      cfg.error_threshold=phase<4 ? 0 : 512;
      cfg.lut_freeze=phase==4;
      cfg.sample_rate=phase==8 ? 0 : (phase==5 ? 2 : 1);
      cfg.qualification_count=phase==6 ? 0 : 3;
      cfg.update_interval=phase==7 ? 4 : 0;
      samples_before=stream_status.sample_count;
      for (int job=0;job<(phase==8 ? 300:40);job++) begin
        wait(legacy_status.ready_flag && stream_ready);
        @(negedge clk); #1;
        legacy_seen=0; stream_seen=0;
        value=19'(((job*9973)%131073)-65536);
        launch=1;
        @(negedge clk); #1; launch=0;
        wait(legacy_seen && stream_seen);
        @(negedge clk); #1;
        if (saved_legacy!==saved_stream) $fatal(1,"Learning result mismatch phase=%0d job=%0d",phase,job);
        if (legacy_status.sample_count!==stream_status.sample_count || legacy_status.fallback_count!==stream_status.fallback_count || legacy_status.max_error!==stream_status.max_error || legacy_status.fallback_flag!==stream_status.fallback_flag || legacy_status.fault_flag!==stream_status.fault_flag)
          $fatal(1,"Adaptive counter mismatch phase=%0d job=%0d",phase,job);
        if (phase==9 && stream_status.sample_count!=samples_before+job+1)
          $fatal(1,"Rate 256->1 did not sample immediately");
        for (int bin=0;bin<8;bin++) begin
          if (legacy.u_iteration_lut.budget_q[bin]!==streaming.budgets[bin] || legacy.forced_full_q[bin]!==streaming.forced[bin] || legacy.success_count_q[bin]!==streaming.successes[bin] || legacy.violation_count_q[bin]!==streaming.violations[bin])
            $fatal(1,"Learning state mismatch phase=%0d job=%0d bin=%0d",phase,job,bin);
        end
        checks++;
      end
    end
    $display("PASS streaming learning matches iterative controller: %0d transactions, all bin states, counters, freeze, sampling and learning reset",checks);
    $finish;
  end
  initial begin #1000000; $fatal(1,"Learning comparison timeout"); end
endmodule
