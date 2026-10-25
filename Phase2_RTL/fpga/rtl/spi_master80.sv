module spi_master80 (
  input logic clk, rst_n, start_i,
  input logic [79:0] tx_i,
  input logic [15:0] half_period_i,
  output logic busy_o, done_o,
  output logic [79:0] rx_o,
  output logic cs_n_o, sck_o, mosi_o,
  input logic miso_i
);
  typedef enum logic [2:0] {IDLE, SETUP, HIGH, LOW, HOLD, GAP} state_t;
  state_t state_q;
  logic [15:0] ticks_q, period_q;
  logic [6:0] bit_q;
  logic [79:0] tx_q, rx_q;
  assign busy_o = state_q != IDLE;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= IDLE; ticks_q <= 0; period_q <= 8; bit_q <= 0;
      tx_q <= 0; rx_q <= 0; rx_o <= 0; done_o <= 0;
      cs_n_o <= 1; sck_o <= 0; mosi_o <= 0;
    end else begin
      done_o <= 0;
      if (state_q == IDLE) begin
        if (start_i) begin
          period_q <= half_period_i < 8 ? 16'd8 : half_period_i;
          ticks_q <= (half_period_i < 8 ? 16'd8 : half_period_i) - 1'b1;
          tx_q <= tx_i; rx_q <= 0; bit_q <= 79;
          cs_n_o <= 0; mosi_o <= tx_i[79]; state_q <= SETUP;
        end
      end else if (ticks_q != 0) ticks_q <= ticks_q - 1'b1;
      else begin
        ticks_q <= period_q - 1'b1;
        case (state_q)
          SETUP, LOW: begin
            sck_o <= 1; rx_q <= {rx_q[78:0], miso_i}; state_q <= HIGH;
          end
          HIGH: begin
            sck_o <= 0;
            if (bit_q == 0) state_q <= HOLD;
            else begin
              bit_q <= bit_q - 1'b1; tx_q <= {tx_q[78:0],1'b0};
              mosi_o <= tx_q[78]; state_q <= LOW;
            end
          end
          HOLD: begin cs_n_o <= 1; mosi_o <= 0; state_q <= GAP; end
          GAP: begin rx_o <= rx_q; done_o <= 1; state_q <= IDLE; end
          default: state_q <= IDLE;
        endcase
      end
    end
  end
endmodule
