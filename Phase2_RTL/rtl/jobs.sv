module stream_job_engine
  import cordic_pkg::*;
#(parameter int LANES=1,parameter int VECTORS=64,parameter bit SHARED_REFERENCE=1) (
  input logic clk,rst_n,
  input logic command_valid_i,
  output logic command_ready_o,
  input logic command_bank_i,
  input logic [$clog2(VECTORS):0] command_count_i,
  input logic [15:0] command_tag_i,
  input csr_to_ctrl_t command_cfg_i,
  input logic command_fused_i,

  input logic command_model_i,
  input logic [127:0] command_weights2_i,command_bias2_i,
  input logic [127:0] command_weights_i,command_bias_i,
  input logic [4:0] command_shift_i,
  output logic command_rejected_o,
  input logic release_i,release_bank_i,
  output logic [1:0] locked_o,done_o,
  output logic [15:0] completed_tag_o [0:1],
  output logic irq_o,
  input logic host_write_i,host_read_i,host_bank_i,
  input logic [(LANES<=1 ? 1:$clog2(LANES))-1:0] host_lane_i,
  input logic [$clog2(VECTORS)-1:0] host_index_i,
  input logic [3:0] host_be_i,
  input logic [31:0] host_wdata_i,
  output logic [31:0] host_rdata_o,
  output logic host_rejected_o,
  output ctrl_to_csr_t lane_status_o [0:LANES-1],

  output logic [31:0] performance_o [0:1][0:6]
);
  localparam int INDEX_WIDTH=$clog2(VECTORS);
  typedef struct packed {
    csr_to_ctrl_t cfg;
    logic bank;
    logic [INDEX_WIDTH:0] count;
    logic [15:0] tag;
    logic fused,model;
    logic [127:0] weights2,bias2;
    logic [127:0] weights,bias;
    logic [4:0] shift;
    logic [31:0] submitted;
  } command_t;
  command_t queued,request,active;
  logic queue_valid,queue_ready;
  logic busy,read_valid,second_layer;
  logic [31:0] hidden_mem [0:VECTORS-1];
  logic [31:0] hidden_read;
  csr_to_ctrl_t layer_cfg;
  always_comb begin
    layer_cfg=active.cfg;
    if (active.model) begin
      layer_cfg.activation_mode=second_layer ? 2'd1 : 2'd0;
      layer_cfg.min_iter=14; layer_cfg.max_iter=14; layer_cfg.full_iter=14;
      layer_cfg.error_threshold=0; layer_cfg.sample_rate=0; layer_cfg.lut_freeze=1;
    end
  end
  function automatic logic signed [7:0] requant(input logic signed [15:0] v);
    integer magnitude,q;
    magnitude=v<0 ? -int'(v) : int'(v);
    q=(magnitude+64)>>7;
    if(v<0) q=-q;
    if(q>127) q=127;
    if(q< -128) q=-128;
    return 8'(q);
  endfunction
  logic [INDEX_WIDTH:0] issued,retired;
  logic [INDEX_WIDTH-1:0] read_index;
  logic [31:0] cycle_q,first_input,first_output,input_count,stall_count,reference_stalls;
  logic input_seen,output_seen;
  wire legal_command=command_count_i!=0 && int'(command_count_i)<=VECTORS &&
    !locked_o[command_bank_i] && command_cfg_i.enable && !command_cfg_i.lut_reset &&
    (!(command_fused_i===1'b1) || LANES==4) &&
    (!(command_model_i===1'b1) || (LANES==4 && command_fused_i===1'b1));
  wire submit=command_valid_i && command_ready_o;
  wire take_job=queue_valid && !busy;
  wire array_ready,array_valid,array_idle;
  wire front_ready,activation_valid,reference_stall;
  wire [LANES*19-1:0] activation_values;
  wire [INDEX_WIDTH-1:0] activation_index;
  wire [LANES*19-1:0] values;
  wire [LANES*16-1:0] results;
  wire [INDEX_WIDTH-1:0] result_index;
  wire fetch=busy && issued<active.count && (!read_valid || front_ready);
  wire accept_input=read_valid && front_ready;
  assign command_ready_o=queue_ready && rst_n;
  assign request={command_cfg_i,command_bank_i,command_count_i,command_tag_i,
                  (command_fused_i===1'b1),(command_model_i===1'b1),command_weights2_i,command_bias2_i,command_weights_i,command_bias_i,command_shift_i,cycle_q};
  assign irq_o=|done_o;
  hardware_command_queue #(.WIDTH($bits(command_t)),.DEPTH(4)) queue (
    .clk,.rst_n,.push_valid_i(submit && legal_command),.push_ready_o(queue_ready),
    .push_data_i(request),.pop_valid_o(queue_valid),.pop_ready_i(!busy),
    .pop_data_o(queued),.count_o());
  activation_ping_pong #(.LANES(LANES),.VECTORS(VECTORS)) buffers (
    .clk,.locked_i(locked_o),.host_write_i,.host_bank_i,.host_lane_i,.host_index_i,
    .host_be_i,.host_wdata_i,.host_reject_o(host_rejected_o),.host_read_i,.host_rdata_o,
    .compute_read_i(fetch && !second_layer),.compute_bank_i(active.bank),.compute_index_i(issued[INDEX_WIDTH-1:0]),
    .values_o(values),.result_write_i(array_valid && (!active.model || second_layer)),.result_bank_i(active.bank),
    .result_index_i(result_index),.results_i(results));
  if (LANES==4) begin : fused_path
    wire mac_ready,mac_valid;
    wire [75:0] mac_values;
    wire [INDEX_WIDTH-1:0] mac_index;
    wire [31:0] int8_values;
    for (genvar l=0;l<4;l++) assign int8_values[l*8 +: 8]=second_layer ? hidden_read[l*8 +: 8] : values[l*19 +: 8];
    mac4_stream #(.TAG_WIDTH(INDEX_WIDTH)) mac (
      .clk,.rst_n,.valid_i(read_valid && active.fused),.ready_o(mac_ready),
      .values_i(int8_values),.weights_i(second_layer ? active.weights2 : active.weights),
      .bias_i(second_layer ? active.bias2 : active.bias),.shift_i(active.model ? 5'd0 : active.shift),
      .tag_i(read_index),.valid_o(mac_valid),.ready_i(array_ready && active.fused),
      .values_o(mac_values),.tag_o(mac_index),.idle_o());
    assign front_ready=active.fused ? mac_ready : array_ready;
    assign activation_valid=active.fused ? mac_valid : read_valid;
    assign activation_values=active.fused ? mac_values : values;
    assign activation_index=active.fused ? mac_index : read_index;
  end else begin : activation_only
    assign front_ready=array_ready;
    assign activation_valid=read_valid;
    assign activation_values=values;
    assign activation_index=read_index;
  end
  activation_stream_array #(.LANES(LANES),.TAG_WIDTH(INDEX_WIDTH),.SHARED_REFERENCE(SHARED_REFERENCE)) array (
    .clk,.rst_n,.csr_i(layer_cfg),.lane_status_o,.valid_i(activation_valid),.ready_o(array_ready),
    .values_i(activation_values),.rounding_i(1'b1),.tag_i(activation_index),.valid_o(array_valid),
    .ready_i(1'b1),.results_o(results),.tag_o(result_index),.idle_o(array_idle),
    .reference_stall_o(reference_stall));
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      locked_o<=0;
      done_o<=0;
      completed_tag_o[0]<=0;
      completed_tag_o[1]<=0;
      command_rejected_o<=0;
      busy<=0;
      second_layer<=0;
      active<='0;
      issued<=0;
      retired<=0;
      read_valid<=0;
      read_index<=0;
      cycle_q<=0;
      first_input<=0; first_output<=0; input_count<=0; stall_count<=0; reference_stalls<=0;
      input_seen<=0; output_seen<=0;
      for (int b=0;b<2;b++) for (int c=0;c<7;c++) performance_o[b][c]<=0;
    end else begin
      cycle_q<=cycle_q+1'b1;
      command_rejected_o<=submit && !legal_command;
      if (release_i && done_o[release_bank_i]) begin
        done_o[release_bank_i]<=0;
        locked_o[release_bank_i]<=0;
      end
      if (submit && legal_command) locked_o[command_bank_i]<=1;
      if (take_job) begin
        active<=queued;
        second_layer<=0;
        busy<=1;
        issued<=0;
        retired<=0;
        read_valid<=0;
        input_seen<=0; output_seen<=0; input_count<=0; stall_count<=0; reference_stalls<=0;
      end else begin
        if (accept_input && !second_layer) begin
          input_count<=input_count+1'b1;
          if (!input_seen) begin first_input<=cycle_q; input_seen<=1; end
        end
        if (busy && read_valid && !front_ready) stall_count<=stall_count+1'b1;
        if (busy && activation_valid && reference_stall) reference_stalls<=reference_stalls+1'b1;
        if (accept_input) read_valid<=0;
        if (fetch) begin
          if(second_layer) hidden_read<=hidden_mem[issued[INDEX_WIDTH-1:0]];
          read_valid<=1;
          read_index<=issued[INDEX_WIDTH-1:0];
          issued<=issued+1'b1;
        end
        if (array_valid) begin
          if ((!active.model || second_layer) && !output_seen) begin first_output<=cycle_q; output_seen<=1; end
          if(active.model && !second_layer)
            for(int l=0;l<LANES && l<4;l++) hidden_mem[result_index][l*8 +: 8]<=requant(results[l*16 +: 16]);
          retired<=retired+1'b1;
          if (retired+1'b1==active.count) begin
            if(active.model && !second_layer) begin
              second_layer<=1; issued<=0; retired<=0; read_valid<=0;
            end else begin
            done_o[active.bank]<=1;
            completed_tag_o[active.bank]<=active.tag;
            busy<=0;
            performance_o[active.bank][0]<=first_input-active.submitted;
            performance_o[active.bank][1]<=(output_seen ? first_output : cycle_q)-first_input;
            performance_o[active.bank][2]<=cycle_q-first_input;
            performance_o[active.bank][3]<=input_count;
            performance_o[active.bank][4]<=32'(retired)+1;
            performance_o[active.bank][5]<=stall_count;
            performance_o[active.bank][6]<=reference_stalls;
            end
          end
        end
      end
    end
  end
endmodule
