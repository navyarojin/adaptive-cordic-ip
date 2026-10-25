module uart_tx #(parameter integer CLK_HZ = 25000000,
                 parameter integer BAUD = 115200) (
  input logic clk, rst_n, start_i,
  input logic [7:0] data_i,
  output logic busy_o, tx_o
);
  localparam integer DIV = (CLK_HZ + BAUD/2)/BAUD;
  logic [15:0] count_q;
  logic [3:0] bits_q;
  logic [9:0] shift_q;
  assign busy_o = bits_q != 0;
  assign tx_o = busy_o ? shift_q[0] : 1'b1;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin count_q <= 0; bits_q <= 0; shift_q <= '1; end
    else if (!busy_o) begin
      if (start_i) begin shift_q <= {1'b1,data_i,1'b0}; bits_q <= 10; count_q <= DIV-1; end
    end else if (count_q != 0) count_q <= count_q - 1'b1;
    else begin count_q <= DIV-1; bits_q <= bits_q - 1'b1; shift_q <= {1'b1,shift_q[9:1]}; end
  end
endmodule
