`ifndef CORDIC_ASHR_SV
`define CORDIC_ASHR_SV


















module cordic_ashr
  import cordic_pkg::*;
(
  input  cordic_word_t           val,
  input  logic [SHIFT_WIDTH-1:0] shift,       
  input  logic                   round_mode,  
  output cordic_word_t           result
);

  cordic_word_t biased;

  
  
  assign biased = round_mode ? (val + (cordic_word_t'(1) <<< (shift - 5'd1))) : val;
  assign result = biased >>> shift;

endmodule : cordic_ashr

`endif 
