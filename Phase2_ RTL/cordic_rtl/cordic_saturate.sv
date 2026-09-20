`ifndef CORDIC_SATURATE_SV
`define CORDIC_SATURATE_SV









module cordic_saturate
  import cordic_pkg::*;
#(
  parameter int IN_WIDTH = INTERNAL_WIDTH + 2  
)(
  input  logic signed [IN_WIDTH-1:0] val,
  output cordic_word_t               val_sat,
  output logic                       overflow
);

  localparam logic signed [IN_WIDTH-1:0] HI =  (1 <<< (INTERNAL_WIDTH-1)) - 1;
  localparam logic signed [IN_WIDTH-1:0] LO = -(1 <<< (INTERNAL_WIDTH-1));

  always_comb begin
    if (val > HI) begin
      val_sat  = cordic_word_t'(HI);
      overflow = 1'b1;
    end else if (val < LO) begin
      val_sat  = cordic_word_t'(LO);
      overflow = 1'b1;
    end else begin
      val_sat  = cordic_word_t'(val);
      overflow = 1'b0;
    end
  end

endmodule : cordic_saturate

`endif 
