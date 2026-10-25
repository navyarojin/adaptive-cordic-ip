module activation_stream_array
  import cordic_pkg::*;
#(parameter int LANES=1,parameter int TAG_WIDTH=1,parameter bit SHARED_REFERENCE=0) (
  input logic clk,rst_n,
  input csr_to_ctrl_t csr_i,
  output ctrl_to_csr_t lane_status_o [0:LANES-1],
  input logic valid_i,
  output logic ready_o,
  input logic [LANES*19-1:0] values_i,
  input logic rounding_i,
  input logic [TAG_WIDTH-1:0] tag_i,
  output logic valid_o,
  input logic ready_i,
  output logic [LANES*16-1:0] results_o,
  output logic [TAG_WIDTH-1:0] tag_o,
  output logic idle_o,
  output wire reference_stall_o
);
  logic [LANES-1:0] lane_ready,lane_valid,lane_idle;
  wire [LANES-1:0] samples,reference_ready;
  logic [LANES-1:0] reference_valid;
  logic signed [15:0] reference_results [0:LANES-1];
  wire reference_dispatch_ready;
  assign reference_stall_o=!reference_dispatch_ready;
  wire [TAG_WIDTH-1:0] tags [0:LANES-1];
  csr_to_ctrl_t active_cfg,cfg_q;
  assign idle_o=&lane_idle;
  assign active_cfg=idle_o ? csr_i : cfg_q;
  assign ready_o=(&lane_ready) && reference_dispatch_ready && (idle_o || csr_i==cfg_q);
  assign valid_o=&lane_valid;
  assign tag_o=tags[0];
  always_ff @(posedge clk) begin
    if (!rst_n) cfg_q<='0;
    else if (valid_i && ready_o && idle_o) cfg_q<=csr_i;
  end
  initial if (LANES!=1 && LANES!=4 && LANES!=8 && LANES!=16)
    $fatal(1,"LANES must be 1, 4, 8, or 16");
  for (genvar lane=0;lane<LANES;lane++) begin : lanes
    qualification_stream #(.TAG_WIDTH(TAG_WIDTH),.EXTERNAL_REFERENCE(SHARED_REFERENCE)) unit (
      .clk,.rst_n,.csr_i(active_cfg),.csr_o(lane_status_o[lane]),
      .valid_i(valid_i && ready_o),.ready_o(lane_ready[lane]),
      .value_i(values_i[lane*19 +: 19]),.rounding_i,.tag_i,
      .valid_o(lane_valid[lane]),.ready_i(ready_i && valid_o),
      .result_o(results_o[lane*16 +: 16]),.tag_o(tags[lane]),
      .idle_o(lane_idle[lane]),.selected_iter_o(),.sample_o(samples[lane]),
      .reference_valid_i(reference_valid[lane]),.reference_result_i(reference_results[lane]),
      .reference_ready_o(reference_ready[lane]));
  end
  if (SHARED_REFERENCE) begin : shared
    localparam int LANE_WIDTH=LANES<=1 ? 1:$clog2(LANES);
    logic [LANES-1:0] pending;
    logic [LANES*19-1:0] saved_values;
    logic saved_rounding;
    logic [LANE_WIDTH-1:0] selected;
    wire full_input_ready,full_output_valid;
    wire [LANE_WIDTH-1:0] output_lane;
    wire signed [15:0] output_value;
    wire full_output_ready=!reference_valid[output_lane] || reference_ready[output_lane];
    assign reference_dispatch_ready=pending=='0;
    always_comb begin
      selected='0;
      for (int l=LANES-1;l>=0;l--) if (pending[l]) selected=LANE_WIDTH'(l);
    end
    cordic_activation_stream #(.TAG_WIDTH(LANE_WIDTH)) full_pipeline (
      .clk,.rst_n,.valid_i(|pending),.ready_o(full_input_ready),
      .value_i(saved_values[selected*19 +: 19]),.mode_i(active_cfg.activation_mode),
      .iterations_i(bounded_full_iter(active_cfg.full_iter,active_cfg.min_iter)),
      .rounding_i(saved_rounding),.tag_i(selected),.valid_o(full_output_valid),
      .ready_i(full_output_ready),.result_o(output_value),.tag_o(output_lane));
    always_ff @(posedge clk) begin
      if (!rst_n) begin
        pending<='0;
        reference_valid<='0;
      end else begin
        for (int l=0;l<LANES;l++)
          if (reference_ready[l]) reference_valid[l]<=0;
        if (full_output_valid && full_output_ready) begin
          reference_valid[output_lane]<=1;
          reference_results[output_lane]<=output_value;
        end
        if ((|pending) && full_input_ready) pending[selected]<=0;
        if (valid_i && ready_o) begin
          pending<=active_cfg.activation_mode<2 ? samples : '0;
          saved_values<=values_i;
          saved_rounding<=rounding_i;
        end
      end
    end
  end else begin : independent
    assign reference_dispatch_ready=1'b1;
    assign reference_valid='0;
    for (genvar l=0;l<LANES;l++) assign reference_results[l]='0;
  end
endmodule
