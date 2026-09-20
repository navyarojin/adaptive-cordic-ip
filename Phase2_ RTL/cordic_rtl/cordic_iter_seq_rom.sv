`ifndef CORDIC_ITER_SEQ_ROM_SV
`define CORDIC_ITER_SEQ_ROM_SV






















module cordic_iter_seq_rom
  import cordic_pkg::*;
(
  input  logic [ITER_CNT_WIDTH-1:0] step,   
  output logic [SHIFT_WIDTH-1:0]    idx     
);

  function automatic logic [SHIFT_WIDTH-1:0] seq_lut(input logic [ITER_CNT_WIDTH-1:0] s);
    case (s)
      4'd0:  seq_lut = 5'd1;
      4'd1:  seq_lut = 5'd2;
      4'd2:  seq_lut = 5'd3;
      4'd3:  seq_lut = 5'd4;
      4'd4:  seq_lut = 5'd4;  
      4'd5:  seq_lut = 5'd5;
      4'd6:  seq_lut = 5'd6;
      4'd7:  seq_lut = 5'd7;
      4'd8:  seq_lut = 5'd8;
      4'd9:  seq_lut = 5'd9;
      4'd10: seq_lut = 5'd10;
      4'd11: seq_lut = 5'd11;
      4'd12: seq_lut = 5'd12;
      4'd13: seq_lut = 5'd13;
      4'd14: seq_lut = 5'd13; 
      4'd15: seq_lut = 5'd14;
      default: seq_lut = 5'd1;
    endcase
  endfunction

  assign idx = seq_lut(step);

endmodule : cordic_iter_seq_rom

`endif 
