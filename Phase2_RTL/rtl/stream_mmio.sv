module stream_mmio
  import cordic_pkg::*;
#(parameter int LANES=4) (
  input logic clk,rst_n,
  input logic cpu_en_i,cpu_we_i,
  input logic [3:0] cpu_be_i,
  input logic [11:0] cpu_addr_i,
  input logic [31:0] cpu_wdata_i,
  output logic [31:0] cpu_rdata_o,
  input logic ps_en_i,
  input logic [3:0] ps_we_i,
  input logic [15:0] ps_addr_i,
  input logic [31:0] ps_wdata_i,
  output logic [31:0] ps_rdata_o,
  output wire irq_o
);
  localparam int LANE_BITS=$clog2(LANES);
  localparam int LANE_WIDTH=LANES<=1 ? 1:LANE_BITS;
  csr_to_ctrl_t cfg;
  ctrl_to_csr_t status [0:LANES-1];
  logic [31:0] descriptor,errors;

  logic fused,model_mode,model_loaded;
  logic [127:0] model_w1,model_b1,model_w2,model_b2;
  logic [4:0] shift;
  logic [127:0] weights,bias;
  wire [31:0] performance [0:1][0:6];
  wire [1:0] locked,done;
  wire [15:0] completed_tags [0:1];
  wire command_ready,command_rejected,host_rejected;
  wire full_cpu_write=cpu_en_i && cpu_we_i && &cpu_be_i && cpu_addr_i[1:0]==0;
  wire submit=full_cpu_write && cpu_addr_i==12'h014 && cpu_wdata_i[0];
  wire release_bank=full_cpu_write && cpu_addr_i==12'h018 && cpu_wdata_i[8];
  wire ps_write=ps_en_i && |ps_we_i;
  wire input_region=ps_addr_i[15:12]==1 || ps_addr_i[15:12]==2;
  wire compact_region=ps_addr_i[15:12]==5 || ps_addr_i[15:12]==6;
  wire output_region=ps_addr_i[15:12]==3 || ps_addr_i[15:12]==4 || compact_region;
  wire in_range=int'(ps_addr_i[11:0])<(compact_region ? 64*4 : LANES*64*4) && ps_addr_i[1:0]==0;
  wire host_bank=compact_region ? ps_addr_i[13] : (input_region ? ps_addr_i[13] : ps_addr_i[14]);
  wire [LANE_WIDTH-1:0] host_lane=(LANES==1 || compact_region) ? '0 : ps_addr_i[2 +: LANE_WIDTH];
  wire [5:0] host_index=compact_region ? ps_addr_i[2 +: 6] : ps_addr_i[2+LANE_BITS +: 6];
  wire [31:0] buffer_data;
  logic ps_buffer_q;
  logic [31:0] ps_control_q,error_next;
  function automatic logic [31:0] read_control(input logic [11:0] address);
    int lane;
    lane=int'(address[11:5])-8;
    case (address)
      12'h000:return 32'h53545231;
      12'h004:return (64<<16)|LANES;
      12'h008:return {14'b0,done,6'b0,locked,7'b0,command_ready};
      12'h00c:return errors;
      12'h010:return descriptor;
      12'h01c:return {completed_tags[1],completed_tags[0]};
      12'h020:return {29'b0,cfg.activation_mode,cfg.enable};
      12'h024:return {8'b0,cfg.full_iter,cfg.max_iter,cfg.min_iter};
      12'h028:return {8'b0,cfg.sample_rate,cfg.error_threshold};
      12'h02c:return {cfg.violation_limit,cfg.qualification_count};
      12'h030:return {15'b0,cfg.lut_freeze,cfg.update_interval};
      12'h034:return 32'h00010001 | (LANES==4 ? 32'h6 : 32'h0);
      12'h038:return {19'b0,shift,6'b0,model_mode,fused};
      12'h03c:return {31'b0,model_loaded};
      default:begin
        if (address>=12'h040 && address<=12'h04c && address[1:0]==0)
          return weights[32*((address-12'h040)>>2) +: 32];
        if (address>=12'h050 && address<=12'h05c && address[1:0]==0)
          return bias[32*((address-12'h050)>>2) +: 32];
        if (address>=12'h080 && address<=12'h098 && address[1:0]==0)
          return performance[0][3'((address-12'h080)>>2)];
        if (address>=12'h0a0 && address<=12'h0b8 && address[1:0]==0)
          return performance[1][3'((address-12'h0a0)>>2)];
        if (lane>=0 && lane<LANES) begin
          case (address[4:0])
            0:return status[lane].sample_count;
            4:return status[lane].fallback_count;
            8:return {16'b0,status[lane].max_error};
            12:return {29'b0,status[lane].ready_flag,status[lane].fallback_flag,status[lane].fault_flag};
            default:return 32'hbad00004;
          endcase
        end
        return 32'hbad00004;
      end
    endcase
  endfunction
  stream_job_engine #(.LANES(LANES),.SHARED_REFERENCE(1)) engine (
    .clk,.rst_n,.command_valid_i(submit && (!model_mode || model_loaded)),.command_ready_o(command_ready),
    .command_bank_i(descriptor[0]),.command_count_i(descriptor[14:8]),
    .command_tag_i(descriptor[31:16]),.command_cfg_i(cfg),.command_rejected_o(command_rejected),
    .command_fused_i(fused),.command_model_i(model_mode && model_loaded),
    .command_weights_i(model_mode ? model_w1 : weights),.command_bias_i(model_mode ? model_b1 : bias),
    .command_weights2_i(model_w2),.command_bias2_i(model_b2),.command_shift_i(shift),
    .release_i(release_bank),.release_bank_i(cpu_wdata_i[0]),.locked_o(locked),.done_o(done),
    .completed_tag_o(completed_tags),.irq_o,
    .host_write_i(ps_write && input_region && in_range),
    .host_read_i(ps_en_i && output_region && in_range),.host_bank_i(host_bank),
    .host_lane_i(host_lane),.host_index_i(host_index),.host_be_i(ps_we_i),.host_wdata_i(ps_wdata_i),
    .host_rdata_o(buffer_data),.host_rejected_o(host_rejected),.lane_status_o(status),.performance_o(performance));
  assign ps_rdata_o=ps_buffer_q ? buffer_data : ps_control_q;
  always_comb begin
    error_next=errors;
    if (full_cpu_write && cpu_addr_i==12'h00c) error_next=error_next & ~cpu_wdata_i;
    if (command_rejected || (submit && (!command_ready || (model_mode && !model_loaded)))) error_next[0]=1;
    if (host_rejected) error_next[1]=1;
    if (ps_write && (!input_region || !in_range)) error_next[2]=1;
    if (cpu_en_i && cpu_we_i && !full_cpu_write) error_next[3]=1;
  end
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cfg<='0;
      cfg.enable<=1;
      cfg.activation_mode<=3;
      cfg.min_iter<=6;
      cfg.max_iter<=14;
      cfg.full_iter<=14;
      cfg.sample_rate<=32;
      cfg.error_threshold<=512;
      cfg.qualification_count<=8;
      cfg.violation_limit<=3;
      cfg.update_interval<=32;
      descriptor<=0;
      model_mode<=0; model_loaded<=0; model_w1<=0; model_b1<=0; model_w2<=0; model_b2<=0;
      fused<=0; shift<=0; weights<=0; bias<=0;
      errors<=0;
      cpu_rdata_o<=0;
      ps_buffer_q<=0;
      ps_control_q<=0;
    end else begin
      errors<=error_next;
      if (cpu_en_i) cpu_rdata_o<=read_control(cpu_addr_i);
      if (ps_en_i) begin
        ps_buffer_q<=output_region && in_range;
        ps_control_q<=ps_addr_i[15:12]==0 ? read_control(ps_addr_i[11:0]) : 32'hbad00004;
      end
      if (full_cpu_write) case (cpu_addr_i)
        12'h010:descriptor<=cpu_wdata_i;
        12'h020:begin cfg.enable<=cpu_wdata_i[0]; cfg.activation_mode<=cpu_wdata_i[2:1]; end
        12'h024:begin cfg.min_iter<=cpu_wdata_i[7:0]; cfg.max_iter<=cpu_wdata_i[15:8]; cfg.full_iter<=cpu_wdata_i[23:16]; end
        12'h028:begin cfg.error_threshold<=cpu_wdata_i[15:0]; cfg.sample_rate<=cpu_wdata_i[23:16]; end
        12'h02c:begin cfg.qualification_count<=cpu_wdata_i[15:0]; cfg.violation_limit<=cpu_wdata_i[31:16]; end
        12'h030:begin cfg.update_interval<=cpu_wdata_i[15:0]; cfg.lut_freeze<=cpu_wdata_i[16]; end
        12'h03c:model_loaded<=cpu_wdata_i[0];
        12'h038:begin model_mode<=cpu_wdata_i[1]; fused<=cpu_wdata_i[0]; shift<=cpu_wdata_i[12:8]; end
        default: begin
          if(cpu_addr_i>=12'h400 && cpu_addr_i<=12'h43c) begin
            model_loaded<=0;
            case(cpu_addr_i[5:4])
              0:model_w1[32*cpu_addr_i[3:2] +: 32]<=cpu_wdata_i;
              1:model_b1[32*cpu_addr_i[3:2] +: 32]<=cpu_wdata_i;
              2:model_w2[32*cpu_addr_i[3:2] +: 32]<=cpu_wdata_i;
              3:model_b2[32*cpu_addr_i[3:2] +: 32]<=cpu_wdata_i;
            endcase
          end
          if (cpu_addr_i>=12'h040 && cpu_addr_i<=12'h04c)
            weights[32*((cpu_addr_i-12'h040)>>2) +: 32]<=cpu_wdata_i;
          if (cpu_addr_i>=12'h050 && cpu_addr_i<=12'h05c)
            bias[32*((cpu_addr_i-12'h050)>>2) +: 32]<=cpu_wdata_i;
        end
      endcase
    end
  end
endmodule
