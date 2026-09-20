`ifndef FX_MUL_ROUND_SV
`define FX_MUL_ROUND_SV






















module fx_mul_round
  import cordic_pkg::*;
(
  input  cordic_word_t a,
  input  cordic_word_t b,
  output cordic_word_t result,
  output logic         overflow
);

  localparam int PROD_WIDTH = 2 * INTERNAL_WIDTH; 

  logic signed [PROD_WIDTH-1:0]     product;
  logic                             prod_sign;
  logic        [PROD_WIDTH-1:0]     prod_mag;
  logic        [PROD_WIDTH-FRAC_BITS-1:0] rounded_mag; 
  logic signed [PROD_WIDTH-FRAC_BITS:0]   signed_result;

  assign product   = a * b;
  assign prod_sign = product[PROD_WIDTH-1];
  assign prod_mag  = prod_sign ? (~product + 1'b1) : product;

  
  
  assign rounded_mag = (prod_mag + (1 <<< (FRAC_BITS-1))) >> FRAC_BITS;

  assign signed_result = prod_sign ? -{1'b0, rounded_mag} : {1'b0, rounded_mag};

  cordic_saturate #(.IN_WIDTH(PROD_WIDTH-FRAC_BITS+1)) u_sat (
    .val(signed_result), .val_sat(result), .overflow(overflow)
  );

endmodule : fx_mul_round

`endif 
