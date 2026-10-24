module fx_signed_divider_stream #(
  parameter int NUM_WIDTH = 32,
  parameter int DEN_WIDTH = 18,
  parameter int QUOTIENT_BITS = NUM_WIDTH,
  parameter int TAG_WIDTH = 1
) (
  input logic clk,
  input logic rst_n,
  input logic valid_i,
  output logic ready_o,
  input logic signed [NUM_WIDTH-1:0] numerator_i,
  input logic signed [DEN_WIDTH-1:0] denominator_i,
  input logic [TAG_WIDTH-1:0] tag_i,
  output logic valid_o,
  input logic ready_i,
  output logic signed [NUM_WIDTH-1:0] quotient_o,
  output logic div_by_zero_o,
  output logic [TAG_WIDTH-1:0] tag_o
);
  typedef struct packed {
    logic [NUM_WIDTH-1:0] numerator;
    logic [NUM_WIDTH-1:0] quotient;
    logic [DEN_WIDTH-1:0] denominator;
    logic [DEN_WIDTH:0] remainder;
    logic negative;
    logic zero;
    logic [TAG_WIDTH-1:0] tag;
  } token_t;
  token_t stage [0:QUOTIENT_BITS];
  logic [QUOTIENT_BITS:0] valid;
  logic [NUM_WIDTH-1:0] numerator_magnitude;
  assign numerator_magnitude=numerator_i[NUM_WIDTH-1] ? -numerator_i : numerator_i;
  wire advance = !valid_o || ready_i;
  assign ready_o = advance && rst_n;
  initial if (NUM_WIDTH<2 || DEN_WIDTH<2 || TAG_WIDTH<1 || QUOTIENT_BITS<1 || QUOTIENT_BITS>NUM_WIDTH || NUM_WIDTH-QUOTIENT_BITS>DEN_WIDTH)
    $fatal(1,"Invalid streaming divider widths");
  always_ff @(posedge clk) begin
    if (!rst_n) valid[0]<=0;
    else if (advance) begin
      valid[0]<=valid_i;
      begin
        stage[0].numerator<=numerator_magnitude<<(NUM_WIDTH-QUOTIENT_BITS);
        stage[0].denominator<=denominator_i[DEN_WIDTH-1] ? -denominator_i : denominator_i;
        stage[0].quotient<='0;
        stage[0].remainder<=(DEN_WIDTH+1)'(numerator_magnitude>>QUOTIENT_BITS);
        stage[0].negative<=numerator_i[NUM_WIDTH-1]^denominator_i[DEN_WIDTH-1];
        stage[0].zero<=denominator_i=='0;
        stage[0].tag<=tag_i;
      end
    end
  end
  for (genvar s=0;s<QUOTIENT_BITS;s++) begin : divide_bit
    token_t next_token;
    logic [DEN_WIDTH+1:0] difference;
    always_comb begin
      next_token=stage[s];
      next_token.remainder={stage[s].remainder[DEN_WIDTH-1:0],stage[s].numerator[NUM_WIDTH-1]};
      next_token.numerator=stage[s].numerator<<1;
      next_token.quotient=stage[s].quotient<<1;
      difference={1'b0,next_token.remainder}-{2'b0,stage[s].denominator};
      if (!difference[DEN_WIDTH+1]) begin
        next_token.remainder=difference[DEN_WIDTH:0];
        next_token.quotient[0]=1;
      end
    end
    always_ff @(posedge clk) begin
      if (!rst_n) valid[s+1]<=0;
      else if (advance) begin
        valid[s+1]<=valid[s];
        stage[s+1]<=next_token;
      end
    end
  end
  logic [NUM_WIDTH-1:0] rounded;
  always_comb begin
    rounded=stage[QUOTIENT_BITS].quotient;
    if ((stage[QUOTIENT_BITS].remainder<<1)>={1'b0,stage[QUOTIENT_BITS].denominator})
      rounded=rounded+1'b1;
  end
  always_ff @(posedge clk) begin
    if (!rst_n) valid_o<=0;
    else if (advance) begin
      valid_o<=valid[QUOTIENT_BITS];
      begin
        quotient_o<=stage[QUOTIENT_BITS].zero ? '0 :
          (stage[QUOTIENT_BITS].negative ? -rounded : rounded);
        div_by_zero_o<=stage[QUOTIENT_BITS].zero;
        tag_o<=stage[QUOTIENT_BITS].tag;
      end
    end
  end
endmodule
