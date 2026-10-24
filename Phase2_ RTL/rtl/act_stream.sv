module cordic_activation_stream #(
  parameter int TAG_WIDTH = 1
) (
  input logic clk, rst_n,
  input logic valid_i,
  output logic ready_o,
  input logic signed [18:0] value_i,
  input logic [1:0] mode_i,
  input logic [4:0] iterations_i,
  input logic rounding_i,
  input logic [TAG_WIDTH-1:0] tag_i,
  output logic valid_o,
  input logic ready_i,
  output logic signed [15:0] result_o,
  output logic [TAG_WIDTH-1:0] tag_o
);
  typedef struct packed {
    logic [TAG_WIDTH-1:0] tag;
    logic [1:0] mode;
    logic rounding;
    logic [1:0] halvings;
    logic saturated;
    logic negative;
    logic signed [18:0] original;
  } metadata_t;
  typedef struct packed {
    metadata_t meta;
    logic signed [18:0] reduced;
    logic signed [17:0] x,y,z;
    logic [4:0] iterations;
  } token_t;
  localparam int META_WIDTH=$bits(metadata_t);
  token_t pipe_q [0:20];
  logic [20:0] valid_q;
  wire divider_ready;
  assign ready_o=divider_ready && rst_n;
  function automatic logic signed [17:0] add_sat18(
    input logic signed [17:0] a,b,input logic subtract);
    logic signed [18:0] sum;
    sum=$signed({a[17],a})+$signed({b[17],b}^{19{subtract}})+19'(subtract);
    if (sum[18:17]==2'b01) return 18'sd131071;
    if (sum[18:17]==2'b10) return -18'sd131072;
    return sum[17:0];
  endfunction
  function automatic logic signed [15:0] sat16(input logic signed [31:0] v);
    if (v>32767) return 16'sd32767;
    if (v< -32768) return -16'sd32768;
    return 16'(v);
  endfunction
  function automatic integer angle(input integer shift);
    case (shift)
      1:return 9000;
      2:return 4185;
      3:return 2059;
      4:return 1025;
      default:return 1<<(14-shift);
    endcase
  endfunction
  logic signed [19:0] effective;
  always_comb begin
    effective={{1{value_i[18]}},value_i};
    if (mode_i==1) effective=(effective+(rounding_i ? 20'sd1 : 20'sd0))>>>1;
  end
  always_ff @(posedge clk) begin
    if (!rst_n) valid_q[0]<=0;
    else if (divider_ready) begin
      valid_q[0]<=valid_i;
      begin
        pipe_q[0]<='0;
        pipe_q[0].meta.tag<=tag_i;
        pipe_q[0].meta.mode<=mode_i;
        pipe_q[0].meta.rounding<=rounding_i;
        pipe_q[0].meta.original<=value_i;
        pipe_q[0].meta.saturated<=effective>=85197 || effective<=-85197;
        pipe_q[0].meta.negative<=effective<0;
        pipe_q[0].reduced<=19'(effective);
        pipe_q[0].iterations<=iterations_i<1 ? 5'd1 : (iterations_i>16 ? 5'd16 : iterations_i);
      end
    end
  end
  for (genvar s=0;s<3;s++) begin : range_reduce
    token_t next_token;
    always_comb begin
      next_token=pipe_q[s];
      if (!pipe_q[s].meta.saturated && (pipe_q[s].reduced>16384 || pipe_q[s].reduced< -16384)) begin
        next_token.reduced=($signed(pipe_q[s].reduced)+(pipe_q[s].meta.rounding ? 19'sd1 : 19'sd0))>>>1;
        next_token.meta.halvings=pipe_q[s].meta.halvings+1'b1;
      end
    end
    always_ff @(posedge clk) begin
      if (!rst_n) valid_q[s+1]<=0;
      else if (divider_ready) begin
        valid_q[s+1]<=valid_q[s];
        pipe_q[s+1]<=next_token;
      end
    end
  end
  always_ff @(posedge clk) begin
    if (!rst_n) valid_q[4]<=0;
    else if (divider_ready) begin
      valid_q[4]<=valid_q[3];
      begin
        pipe_q[4]<=pipe_q[3];
        pipe_q[4].x<=18'sd16384;
        pipe_q[4].y<=0;
        pipe_q[4].z<=18'(pipe_q[3].reduced);
      end
    end
  end
  for (genvar s=0;s<16;s++) begin : rotation
    localparam int SHIFT=s<4 ? s+1 : (s<14 ? s : s-1);
    token_t next_token;
    logic signed [17:0] dx,dy;
    always_comb begin
      next_token=pipe_q[s+4];
      dx=18'((19'($signed(pipe_q[s+4].x))+(pipe_q[s+4].meta.rounding ? 19'sd1<<(SHIFT-1):19'sd0))>>>SHIFT);
      dy=18'((19'($signed(pipe_q[s+4].y))+(pipe_q[s+4].meta.rounding ? 19'sd1<<(SHIFT-1):19'sd0))>>>SHIFT);
      if (s<pipe_q[s+4].iterations) begin
        next_token.x=add_sat18(pipe_q[s+4].x,dy,pipe_q[s+4].z[17]);
        next_token.y=add_sat18(pipe_q[s+4].y,dx,pipe_q[s+4].z[17]);
        next_token.z=add_sat18(pipe_q[s+4].z,18'(angle(SHIFT)),!pipe_q[s+4].z[17]);
      end
    end
    always_ff @(posedge clk) begin
      if (!rst_n) valid_q[s+5]<=0;
      else if (divider_ready) begin
        valid_q[s+5]<=valid_q[s+4];
        pipe_q[s+5]<=next_token;
      end
    end
  end
  wire [3:0] div_valid, div_ready;
  wire signed [31:0] div_value [0:3];
  metadata_t div_meta [0:3];
  wire [3:0] div_zero;
  fx_signed_divider_stream #(.TAG_WIDTH(META_WIDTH),.QUOTIENT_BITS(16)) initial_ratio (
    .clk,.rst_n,.valid_i(valid_q[20]),.ready_o(divider_ready),
    .numerator_i(32'($signed(pipe_q[20].y))<<<14),.denominator_i(pipe_q[20].x),
    .tag_i(pipe_q[20].meta),.valid_o(div_valid[0]),.ready_i(div_ready[0]),
    .quotient_o(div_value[0]),.div_by_zero_o(div_zero[0]),.tag_o(div_meta[0]));
  for (genvar s=0;s<3;s++) begin : reconstruct
    logic signed [31:0] square;
    logic signed [15:0] bounded_value;
    logic signed [31:0] numerator;
    logic signed [17:0] denominator;
    always_comb begin
      bounded_value=16'(div_value[s]);
      square=bounded_value*bounded_value;
      numerator=32'($signed(bounded_value));
      denominator=18'sd1;
      if (div_meta[s].halvings>s) begin
        numerator=32'($signed(bounded_value))<<<15;
        denominator=18'(16384+((square+8192)>>>14));
      end
    end
    fx_signed_divider_stream #(.TAG_WIDTH(META_WIDTH),.QUOTIENT_BITS(16)) double_angle (
      .clk,.rst_n,.valid_i(div_valid[s]),.ready_o(div_ready[s]),
      .numerator_i(numerator),.denominator_i(denominator),.tag_i(div_meta[s]),
      .valid_o(div_valid[s+1]),.ready_i(div_ready[s+1]),
      .quotient_o(div_value[s+1]),.div_by_zero_o(div_zero[s+1]),.tag_o(div_meta[s+1]));
  end
  assign div_ready[3]=ready_i;
  assign valid_o=div_valid[3];
  assign tag_o=div_meta[3].tag;
  logic signed [31:0] final_value;
  always_comb begin
    final_value=32'($signed(sat16(div_value[3])));
    if (div_meta[3].saturated) final_value=div_meta[3].negative ? -16384 : 16383;
    case (div_meta[3].mode)
      1: final_value=(16384+final_value+32'(div_meta[3].rounding))>>>1;
      2: final_value=div_meta[3].original<0 ? 0 : 32'($signed(div_meta[3].original));
      3: final_value=32'($signed(div_meta[3].original));
      default: ;
    endcase
    result_o=sat16(final_value);
  end
endmodule
