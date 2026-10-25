module cv32e40p_sleep_unit #(
    parameter COREV_CLUSTER = 0
) (

    input  logic clk_ungated_i,
    input  logic rst_n,
    output logic clk_gated_o,
    input  logic scan_cg_en_i,

    output logic core_sleep_o,

    input  logic fetch_enable_i,
    output logic fetch_enable_o,

    input logic if_busy_i,
    input logic ctrl_busy_i,
    input logic lsu_busy_i,
    input logic apu_busy_i,

    input logic pulp_clock_en_i,
    input logic p_elw_start_i,
    input logic p_elw_finish_i,
    input logic debug_p_elw_no_sleep_i,

    input logic wake_from_sleep_i
);

  import cv32e40p_pkg::*;

  logic fetch_enable_q;
  logic fetch_enable_d;
  logic              core_busy_q;
  logic core_busy_d;
  logic p_elw_busy_q;
  logic p_elw_busy_d;
  logic clock_en;

  assign fetch_enable_d = fetch_enable_i ? 1'b1 : fetch_enable_q;

  generate
    if (COREV_CLUSTER) begin : g_pulp_sleep

      assign core_busy_d = p_elw_busy_d ? (if_busy_i || apu_busy_i) : 1'b1;

      assign clock_en = fetch_enable_q && (pulp_clock_en_i || core_busy_q);

      assign core_sleep_o = p_elw_busy_d && !core_busy_q && !debug_p_elw_no_sleep_i;

      assign p_elw_busy_d = p_elw_start_i ? 1'b1 : (p_elw_finish_i ? 1'b0 : p_elw_busy_q);

    end else begin : g_no_pulp_sleep

      assign core_busy_d = if_busy_i || ctrl_busy_i || lsu_busy_i || apu_busy_i;

      assign clock_en = fetch_enable_q && (wake_from_sleep_i || core_busy_q);

      assign core_sleep_o = fetch_enable_q && !clock_en;

      assign p_elw_busy_d = 1'b0;

    end
  endgenerate

  always_ff @(posedge clk_ungated_i, negedge rst_n) begin
    if (rst_n == 1'b0) begin
      core_busy_q    <= 1'b0;
      p_elw_busy_q   <= 1'b0;
      fetch_enable_q <= 1'b0;
    end else begin
      core_busy_q    <= core_busy_d;
      p_elw_busy_q   <= p_elw_busy_d;
      fetch_enable_q <= fetch_enable_d;
    end
  end

  assign fetch_enable_o = fetch_enable_q;

  cv32e40p_clock_gate core_clock_gate_i (
      .clk_i       (clk_ungated_i),
      .en_i        (clock_en),
      .scan_cg_en_i(scan_cg_en_i),
      .clk_o       (clk_gated_o)
  );

`ifdef CV32E40P_ASSERT_ON

  property p_clock_en_0;
    @(posedge clk_ungated_i) disable iff (!rst_n) ((id_stage_i.controller_i.ctrl_fsm_cs == cv32e40p_pkg::RESET) && (id_stage_i.controller_i.ctrl_fsm_ns == cv32e40p_pkg::RESET)) |-> (clock_en == 1'b0);
  endproperty

  a_clock_en_0 :
  assert property (p_clock_en_0);

  property p_clock_en_1;
    @(posedge clk_ungated_i) disable iff (!rst_n) ((id_stage_i.controller_i.ctrl_fsm_cs == cv32e40p_pkg::RESET) && (id_stage_i.controller_i.ctrl_fsm_ns != cv32e40p_pkg::RESET)) |-> (clock_en == 1'b1);
  endproperty

  a_clock_en_1 :
  assert property (p_clock_en_1);

  property p_clock_en_2;
    @(posedge clk_ungated_i) disable iff (!rst_n) (fetch_enable_q == 1'b0) |-> (clock_en == 1'b0);
  endproperty

  a_clock_en_2 :
  assert property (p_clock_en_2);

  generate
    if (COREV_CLUSTER) begin : g_pulp_cluster_assertions

      property p_clock_en_3;
        @(posedge clk_ungated_i) disable iff (!rst_n) (clock_en == 1'b0) -> ((id_stage_i.controller_i.ctrl_fsm_cs == cv32e40p_pkg::RESET) || (COREV_CLUSTER && !pulp_clock_en_i));
      endproperty

      a_clock_en_3 :
      assert property (p_clock_en_3);

      property p_only_sleep_during_p_elw;
        @(posedge clk_ungated_i) disable iff (!rst_n) (core_sleep_o == 1'b1) |-> (p_elw_busy_d == 1'b1);
      endproperty

      a_only_sleep_during_p_elw :
      assert property (p_only_sleep_during_p_elw);

      property p_full_clock_en_control;
        @(posedge clk_ungated_i) disable iff (!rst_n) (core_sleep_o == 1'b1) |-> (pulp_clock_en_i == clock_en);
      endproperty

      a_full_clock_en_control :
      assert property (p_full_clock_en_control);

    end else begin : g_no_pulp_cluster_assertions

      property p_clock_en_4;
        @(posedge clk_ungated_i) disable iff (!rst_n) (clock_en == 1'b0) -> ((id_stage_i.controller_i.ctrl_fsm_cs == cv32e40p_pkg::RESET) || (id_stage_i.controller_i.ctrl_fsm_ns == cv32e40p_pkg::SLEEP));
      endproperty

      a_clock_en_4 :
      assert property (p_clock_en_4);

      property p_clock_en_5;
        @(posedge clk_ungated_i) disable iff (!rst_n)  ((id_stage_i.controller_i.ctrl_fsm_cs == cv32e40p_pkg::SLEEP) && (id_stage_i.controller_i.ctrl_fsm_ns != cv32e40p_pkg::SLEEP)) |-> (clock_en == 1'b1);
      endproperty

      a_clock_en_5 :
      assert property (p_clock_en_5);

      property p_core_sleep;
        @(posedge clk_ungated_i) disable iff (!rst_n) (core_sleep_o == 1'b1) -> ((id_stage_i.controller_i.ctrl_fsm_cs == cv32e40p_pkg::SLEEP));
      endproperty

      a_core_sleep :
      assert property (p_core_sleep);

      property p_non_busy;
        @(posedge clk_ungated_i) disable iff (!rst_n) (core_busy_d == 1'b0) |-> (id_stage_i.controller_i.ctrl_fsm_cs == cv32e40p_pkg::WAIT_SLEEP) || (id_stage_i.controller_i.ctrl_fsm_cs == cv32e40p_pkg::SLEEP);
      endproperty

      a_non_busy :
      assert property (p_non_busy);

      property p_gate_clk_i;
        @(posedge clk_ungated_i) disable iff (!rst_n) (core_sleep_o == 1'b1) |-> (core_busy_q == core_busy_d) && (p_elw_busy_q == p_elw_busy_d) && (fetch_enable_q == fetch_enable_d);
      endproperty

      a_gate_clk_i :
      assert property (p_gate_clk_i);

      property p_gate_clock_during_sleep;
        @(posedge clk_ungated_i) disable iff (!rst_n) (core_sleep_o == 1'b1) |-> (clock_en == 1'b0);
      endproperty

      a_gate_clock_during_sleep :
      assert property (p_gate_clock_during_sleep);

      property p_only_sleep_for_wfi;
        @(posedge clk_ungated_i) disable iff (!rst_n) (core_sleep_o == 1'b1) |-> (id_stage_i.instr == {
          12'b000100000101, 13'b0, OPCODE_SYSTEM
        });
      endproperty

      a_only_sleep_for_wfi :
      assert property (p_only_sleep_for_wfi);

      property p_not_busy_during_sleep;
        @(posedge clk_ungated_i) disable iff (!rst_n) (core_sleep_o == 1'b1) |-> ((core_busy_q == 1'b0) && (core_busy_d == 1'b0));
      endproperty

      a_not_busy_during_sleep :
      assert property (p_not_busy_during_sleep);

    end
  endgenerate

`endif

endmodule
