module host_ram #(parameter INIT_FILE = "firmware.mem") (
  input logic clk,
  input logic i_en,
  input logic [15:0] i_addr,
  output logic [31:0] i_rdata,
  input logic d_en, d_we,
  input logic [3:0] d_be,
  input logic [15:0] d_addr,
  input logic [31:0] d_wdata,
  output logic [31:0] d_rdata
);
  (* ram_style = "block" *) logic [31:0] mem [0:16383];
  initial $readmemh(INIT_FILE, mem);
  always @(posedge clk) if (i_en) i_rdata <= mem[i_addr[15:2]];
  always @(posedge clk) if (d_en) begin
    d_rdata <= mem[d_addr[15:2]];
    for (integer b = 0; b < 4; b = b + 1)
      if (d_we && d_be[b]) mem[d_addr[15:2]][b*8 +: 8] <= d_wdata[b*8 +: 8];
  end
endmodule
