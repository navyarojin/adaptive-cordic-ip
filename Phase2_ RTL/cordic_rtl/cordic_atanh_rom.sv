`ifndef CORDIC_ATANH_ROM_SV
`define CORDIC_ATANH_ROM_SV





















module cordic_atanh_rom
  import cordic_pkg::*;
(
  input  logic [SHIFT_WIDTH-1:0] idx,        
  output cordic_word_t           atanh_val
);

  function automatic cordic_word_t rom_lut(input logic [SHIFT_WIDTH-1:0] i);
    case (i)
      5'd1:  rom_lut = 18'sd9000;  
      5'd2:  rom_lut = 18'sd4185;  
      5'd3:  rom_lut = 18'sd2059;  
      5'd4:  rom_lut = 18'sd1025;  
      5'd5:  rom_lut = 18'sd512;   
      5'd6:  rom_lut = 18'sd256;   
      5'd7:  rom_lut = 18'sd128;   
      5'd8:  rom_lut = 18'sd64;    
      5'd9:  rom_lut = 18'sd32;    
      5'd10: rom_lut = 18'sd16;    
      5'd11: rom_lut = 18'sd8;     
      5'd12: rom_lut = 18'sd4;     
      5'd13: rom_lut = 18'sd2;     
      5'd14: rom_lut = 18'sd1;     
      5'd15: rom_lut = 18'sd1;     
      5'd16: rom_lut = 18'sd0;
      5'd17: rom_lut = 18'sd0;
      5'd18: rom_lut = 18'sd0;
      5'd19: rom_lut = 18'sd0;
      default: rom_lut = 18'sd0;
    endcase
  endfunction

  assign atanh_val = rom_lut(idx);

endmodule : cordic_atanh_rom

`endif 
