module qualification_stream
  import cordic_pkg::*;
#(parameter int TAG_WIDTH=1,parameter bit EXTERNAL_REFERENCE=0) (
  input logic clk,rst_n,
  input csr_to_ctrl_t csr_i,
  output ctrl_to_csr_t csr_o,
  input logic valid_i,
  output logic ready_o,
  input logic signed [18:0] value_i,
  input logic rounding_i,
  input logic [TAG_WIDTH-1:0] tag_i,
  output logic valid_o,
  input logic ready_i,
  output logic signed [15:0] result_o,
  output logic [TAG_WIDTH-1:0] tag_o,
  output logic idle_o,
  output logic [4:0] selected_iter_o,
  output logic sample_o,
  input logic reference_valid_i,
  input logic signed [15:0] reference_result_i,
  output logic reference_ready_o
);
  typedef struct packed {
    logic [TAG_WIDTH-1:0] tag;
    logic [2:0] bin;
    logic sample;
    logic nonlinear;
  } tag_t;
  localparam int PIPE_TAG_WIDTH=$bits(tag_t);
  ctrl_to_csr_t status_q;
  logic [4:0] budgets [0:7];
  logic [15:0] successes [0:7],violations [0:7];
  logic [7:0] forced;
  logic [7:0] sample_phase;
  logic [15:0] update_age;
  logic [9:0] outstanding;
  logic [4:0] minimum,maximum,full,selected;
  logic [18:0] magnitude;
  logic [2:0] bin;
  logic sample_request;
  tag_t input_tag,early_tag,full_tag;
  wire early_ready,full_ready,early_valid,full_valid;
  wire signed [15:0] early_result,full_result;
  wire accept=valid_i && ready_o;
  wire retire=valid_o && ready_i;
  logic [16:0] residual;
  logic signed [16:0] difference;
  wire failure=early_tag.sample && residual>{1'b0,csr_i.error_threshold};
  wire force_full=failure && csr_i.violation_limit!=0 &&
    (17'(violations[early_tag.bin])+1>=17'(csr_i.violation_limit));
  wire reduce=early_tag.sample && !failure && budgets[early_tag.bin]>minimum &&
    (csr_i.qualification_count==0 || 17'(successes[early_tag.bin])+1>=17'(csr_i.qualification_count));
  wire update_allowed=csr_i.update_interval==0 || update_age>=csr_i.update_interval;
  wire update_lut=!csr_i.lut_freeze && (failure || (reduce && update_allowed));
  assign idle_o=outstanding==0;
  assign ready_o=early_ready && full_ready && csr_i.enable && !csr_i.lut_reset;
  wire needs_reference=!EXTERNAL_REFERENCE || early_tag.sample;
  assign valid_o=early_valid && (!needs_reference || full_valid);
  assign reference_ready_o=ready_i && early_valid && needs_reference;
  assign result_o=failure ? full_result : early_result;
  assign tag_o=early_tag.tag;
  assign selected_iter_o=selected;
  assign sample_o=sample_request;
  always_comb begin
    minimum=csr_i.min_iter<6 ? 5'd6 : (csr_i.min_iter>16 ? 5'd16 : 5'(csr_i.min_iter));
    maximum=csr_i.max_iter<{3'b0,minimum} ? minimum : (csr_i.max_iter>16 ? 5'd16 : 5'(csr_i.max_iter));
    full=bounded_full_iter(csr_i.full_iter,csr_i.min_iter);
    magnitude=value_i[18] ? -value_i : value_i;
    bin=magnitude[18:14]>=7 ? 3'd7 : magnitude[16:14];
    selected=budgets[bin];
    if (selected<minimum) selected=minimum;
    if (selected>maximum) selected=maximum;
    if (selected>full || forced[bin]) selected=full;

    sample_request=csr_i.sample_rate==0 ? sample_phase==255 : sample_phase>=csr_i.sample_rate-1'b1;
    input_tag.tag=tag_i;
    input_tag.bin=bin;
    input_tag.nonlinear=csr_i.activation_mode<2;
    input_tag.sample=sample_request && input_tag.nonlinear;
    difference=$signed({early_result[15],early_result})-$signed({full_result[15],full_result});
    residual=difference<0 ? -difference : difference;
    csr_o=status_q;
    csr_o.ready_flag=ready_o;
  end
  cordic_activation_stream #(.TAG_WIDTH(PIPE_TAG_WIDTH)) early_pipe (
    .clk,.rst_n,.valid_i(accept),.ready_o(early_ready),.value_i,
    .mode_i(csr_i.activation_mode),.iterations_i(selected),.rounding_i,.tag_i(input_tag),
    .valid_o(early_valid),.ready_i(ready_i && (!needs_reference || full_valid)),.result_o(early_result),.tag_o(early_tag));
  if (EXTERNAL_REFERENCE) begin : shared_reference
    assign full_valid=reference_valid_i;
    assign full_result=reference_result_i;
    assign full_ready=1'b1;
    assign full_tag='0;
  end else begin : local_reference
    cordic_activation_stream #(.TAG_WIDTH(PIPE_TAG_WIDTH)) reference_pipe (
    .clk,.rst_n,.valid_i(accept),.ready_o(full_ready),.value_i,
    .mode_i(csr_i.activation_mode),.iterations_i(full),.rounding_i,.tag_i(input_tag),
    .valid_o(full_valid),.ready_i(reference_ready_o),.result_o(full_result),.tag_o(full_tag));
  end
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      status_q.ready_flag<=0;
      outstanding<=0;
      sample_phase<=0;
      update_age<=16'hffff;
      forced<=0;
      status_q.sample_count<=0;
      status_q.max_error<=0;
      status_q.fallback_count<=0;
      status_q.fault_flag<=0;
      status_q.fallback_flag<=0;
      for (int b=0;b<8;b++) begin
        budgets[b]<=5'(MAG_BIN_SEED_BUDGET[b]);
        successes[b]<=0;
        violations[b]<=0;
      end
    end else begin
      case ({accept,retire})
        2'b10:outstanding<=outstanding+1'b1;
        2'b01:outstanding<=outstanding-1'b1;
        default: ;
      endcase
      if (csr_i.lut_reset && idle_o) begin
        sample_phase<=0;
        update_age<=16'hffff;
        forced<=0;
        status_q.fault_flag<=0;
        status_q.fallback_flag<=0;
        for (int b=0;b<8;b++) begin
          budgets[b]<=5'(MAG_BIN_SEED_BUDGET[b]);
          successes[b]<=0;
          violations[b]<=0;
        end
      end else begin
        if (accept && input_tag.nonlinear)
          sample_phase<=sample_request ? 8'd0 : sample_phase+1'b1;
        if (retire && early_tag.nonlinear) begin
          if (update_age!=16'hffff) update_age<=update_age+1'b1;
          if (early_tag.sample) begin
            status_q.sample_count<=status_q.sample_count+1'b1;
            if (residual>{1'b0,status_q.max_error}) status_q.max_error<=16'(residual);
            if (failure) begin
              status_q.fallback_count<=status_q.fallback_count+1'b1;
              status_q.fallback_flag<=1;
              successes[early_tag.bin]<=0;
              if (violations[early_tag.bin]!=16'hffff) violations[early_tag.bin]<=violations[early_tag.bin]+1'b1;
              if (force_full) forced[early_tag.bin]<=1;
            end else begin
              violations[early_tag.bin]<=0;
              if (csr_i.qualification_count==0 || 17'(successes[early_tag.bin])+1>=17'(csr_i.qualification_count))
                successes[early_tag.bin]<=0;
              else if (successes[early_tag.bin]!=16'hffff) successes[early_tag.bin]<=successes[early_tag.bin]+1'b1;
            end
            if (update_lut) begin
              update_age<=0;
              if (force_full) budgets[early_tag.bin]<=full;
              else if (failure && budgets[early_tag.bin]<maximum) budgets[early_tag.bin]<=budgets[early_tag.bin]+1'b1;
              else if (!failure && reduce) budgets[early_tag.bin]<=budgets[early_tag.bin]-1'b1;
            end
          end
        end
      end
    end
  end
endmodule
