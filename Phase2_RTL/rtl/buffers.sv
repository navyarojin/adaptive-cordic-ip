module activation_ping_pong #(
  parameter int LANES=4,
  parameter int VECTORS=64,
  parameter int INDEX_WIDTH=$clog2(VECTORS),
  parameter int LANE_WIDTH=LANES<=1 ? 1 : $clog2(LANES)
) (
  input logic clk,
  input logic [1:0] locked_i,
  input logic host_write_i,host_bank_i,
  input logic [LANE_WIDTH-1:0] host_lane_i,
  input logic [INDEX_WIDTH-1:0] host_index_i,
  input logic [3:0] host_be_i,
  input logic [31:0] host_wdata_i,
  output logic host_reject_o,
  input logic host_read_i,
  output logic [31:0] host_rdata_o,
  input logic compute_read_i,compute_bank_i,
  input logic [INDEX_WIDTH-1:0] compute_index_i,
  output logic [LANES*19-1:0] values_o,
  input logic result_write_i,result_bank_i,
  input logic [INDEX_WIDTH-1:0] result_index_i,
  input logic [LANES*16-1:0] results_i
);
  logic [31:0] host_words [0:1][0:LANES-1];
  logic selected_bank;
  logic [LANE_WIDTH-1:0] selected_lane;
  logic [18:0] compute_words [0:1][0:LANES-1];
  logic selected_compute_bank;
  assign host_reject_o=host_write_i && (locked_i[host_bank_i] || int'(host_lane_i)>=LANES);
  assign host_rdata_o=int'(selected_lane)<LANES ? host_words[selected_bank][selected_lane] : 32'hbad00003;
  always_ff @(posedge clk) begin
    if (host_read_i) begin selected_bank<=host_bank_i; selected_lane<=host_lane_i; end
    if (compute_read_i) selected_compute_bank<=compute_bank_i;
  end
  for (genvar b=0;b<2;b++) begin : banks
    for (genvar l=0;l<LANES;l++) begin : lanes
      (* ram_style="block" *) logic [31:0] input_mem [0:VECTORS-1];
      (* ram_style="block" *) logic [31:0] output_mem [0:VECTORS-1];
      always_ff @(posedge clk) begin
        if (host_write_i && !locked_i[b] && host_bank_i==b && host_lane_i==l)
          for (int byte_index=0;byte_index<4;byte_index++)
            if (host_be_i[byte_index]) input_mem[host_index_i][byte_index*8 +: 8]<=host_wdata_i[byte_index*8 +: 8];
        if (compute_read_i && compute_bank_i==b)
          compute_words[b][l]<=input_mem[compute_index_i][18:0];
        if (result_write_i && result_bank_i==b)
          output_mem[result_index_i]<={{16{results_i[l*16+15]}},results_i[l*16 +: 16]};
        if (host_read_i && host_bank_i==b)
          host_words[b][l]<=output_mem[host_index_i];
      end
    end
  end
  for (genvar l=0;l<LANES;l++) begin : read_lanes
    assign values_o[l*19 +: 19]=compute_words[selected_compute_bank][l];
  end
endmodule
