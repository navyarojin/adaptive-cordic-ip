module mac4_stream #(parameter int TAG_WIDTH=6) (
  input logic clk,rst_n,
  input logic valid_i, output logic ready_o,
  input logic [31:0] values_i,
  input logic [127:0] weights_i,bias_i,
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
  always_ff @(posedge clk) begin
    if (!rst_n) valid_q<=0;
    else if (advance) begin
      valid_q<={valid_q[2:0],valid_i};
      tag_q[0]<=tag_i;
      for (int s=1;s<4;s++) tag_q[s]<=tag_q[s-1];
      bias_q[0]<=bias_i; bias_q[1]<=bias_q[0];
      shift_q[0]<=shift_i; shift_q[1]<=shift_q[0]; shift_q[2]<=shift_q[1];
      for (int r=0;r<4;r++) begin
        for (int c=0;c<4;c++)
          product_q[r][c]<=$signed(values_i[c*8 +: 8])*$signed(weights_i[(r*4+c)*8 +: 8]);
        pair_q[r][0]<=$signed({product_q[r][0][15],product_q[r][0]})+$signed({product_q[r][1][15],product_q[r][1]});
        pair_q[r][1]<=$signed({product_q[r][2][15],product_q[r][2]})+$signed({product_q[r][3][15],product_q[r][3]});
        sum_q[r]<=$signed({{17{pair_q[r][0][16]}},pair_q[r][0]})+
                  $signed({{17{pair_q[r][1][16]}},pair_q[r][1]})+
                  $signed({{2{bias_q[1][r*32+31]}},bias_q[1][r*32 +: 32]});
        values_o[r*19 +: 19]<=scale(sum_q[r],shift_q[2]);
      end
    end
  end
endmodule
