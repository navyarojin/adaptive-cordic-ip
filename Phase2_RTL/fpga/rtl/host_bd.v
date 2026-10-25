module jupyter_npu_bd (
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst_n, FREQ_HZ 25000000" *)
  input wire clk,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input wire rst_n,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM CLK" *)
  input wire s_bram_clk,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM RST" *)
  input wire s_bram_rst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM EN" *)
  input wire s_bram_en,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM WE" *)
  input wire [3:0] s_bram_we,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM ADDR" *)
  input wire [11:0] s_bram_addr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM DIN" *)
  input wire [31:0] s_bram_wrdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 S_BRAM DOUT" *)
  (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL, MEM_SIZE 4096, READ_WRITE_MODE READ_WRITE" *)
  output wire [31:0] s_bram_rddata,
  output wire [3:0] led,
  output wire uart_tx
);
  jupyter_npu core (.clk(clk), .rst_n(rst_n), .s_bram_clk(s_bram_clk),
    .s_bram_rst(s_bram_rst), .s_bram_en(s_bram_en), .s_bram_we(s_bram_we),
    .s_bram_addr(s_bram_addr), .s_bram_wrdata(s_bram_wrdata),
    .s_bram_rddata(s_bram_rddata), .led(led), .uart_tx(uart_tx));
endmodule
