module mac4_stream #(parameter int TAG_WIDTH=6,parameter bit ENABLE_GATING=1) (
  input logic clk,rst_n,
  input logic valid_i, output logic ready_o,
  input logic [31:0] values_i,
  input logic [127:0] weights_i,bias_i,
  input logic [3:0] row_active_i,
  input logic [4:0] shift_i,
  input logic [TAG_WIDTH-1:0] tag_i,
  output logic valid_o, input logic ready_i,
  output logic [75:0] values_o,
  output logic [TAG_WIDTH-1:0] tag_o,
  output logic idle_o
);
  logic [3:0] valid_q;
  logic signed [15:0] product_q [0:3][0:3];
  logic signed [16:0] pair_q [0:3][0:1];
  logic signed [33:0] sum_q [0:3];
  logic [127:0] bias_q [0:1];
  logic [4:0] shift_q [0:2];
  logic [TAG_WIDTH-1:0] tag_q [0:3];
  logic [3:0] row_active_q [0:1];
  wire advance=!valid_q[3] || ready_i;
  assign ready_o=rst_n && advance;
  assign valid_o=valid_q[3];
  assign tag_o=tag_q[3];
  assign idle_o=valid_q==0;
  function automatic logic signed [18:0] scale(input logic signed [33:0] value,input logic [4:0] amount);
    logic signed [63:0] wide,magnitude,rounded;
    wide={{30{value[33]}},value};
    magnitude=wide<0 ? -wide : wide;
    rounded=amount==0 ? magnitude : (magnitude+(64'sd1<<(amount-1)))>>>amount;
    if (wide<0) rounded=-rounded;
    if (rounded>262143) return 19'sd262143;
    if (rounded< -262144) return -19'sd262144;
    return rounded[18:0];
  endfunction
  wire signed [7:0] multiply_values [0:3][0:3];
  for (genvar r=0;r<4;r++) begin : row_operands
    for (genvar c=0;c<4;c++) begin : column
      assign multiply_values[r][c]=(ENABLE_GATING && !row_active_i[r]) ? 8'sd0 : $signed(values_i[c*8 +: 8]);
    end
  end
  always_ff @(posedge clk) begin
    if (!rst_n) begin valid_q<=0; row_active_q[0]<=0; row_active_q[1]<=0; end
    else if (advance) begin
      valid_q<={valid_q[2:0],valid_i};
      if (!ENABLE_GATING || valid_i) begin
        tag_q[0]<=tag_i;
        bias_q[0]<=bias_i;
        shift_q[0]<=shift_i;
        row_active_q[0]<=row_active_i;
      end
      for (int s=1;s<4;s++) if (!ENABLE_GATING || valid_q[s-1]) tag_q[s]<=tag_q[s-1];
      if (!ENABLE_GATING || valid_q[0]) begin
        bias_q[1]<=bias_q[0];
        shift_q[1]<=shift_q[0];
        row_active_q[1]<=row_active_q[0];
      end
      if (!ENABLE_GATING || valid_q[1]) shift_q[2]<=shift_q[1];
      for (int r=0;r<4;r++) begin
        if (!ENABLE_GATING || (valid_i && row_active_i[r]))
          for (int c=0;c<4;c++)
            product_q[r][c]<=multiply_values[r][c]*$signed(weights_i[(r*4+c)*8 +: 8]);
        if (!ENABLE_GATING || (valid_q[0] && row_active_q[0][r])) begin
          pair_q[r][0]<=$signed({product_q[r][0][15],product_q[r][0]})+$signed({product_q[r][1][15],product_q[r][1]});
          pair_q[r][1]<=$signed({product_q[r][2][15],product_q[r][2]})+$signed({product_q[r][3][15],product_q[r][3]});
        end
        if (!ENABLE_GATING || valid_q[1]) begin
          if (ENABLE_GATING && !row_active_q[1][r])
            sum_q[r]<=$signed({{2{bias_q[1][r*32+31]}},bias_q[1][r*32 +: 32]});
          else sum_q[r]<=$signed({{17{pair_q[r][0][16]}},pair_q[r][0]})+
                         $signed({{17{pair_q[r][1][16]}},pair_q[r][1]})+
                         $signed({{2{bias_q[1][r*32+31]}},bias_q[1][r*32 +: 32]});
        end
        if (!ENABLE_GATING || valid_q[2]) values_o[r*19 +: 19]<=scale(sum_q[r],shift_q[2]);
      end
    end
  end
endmodule
