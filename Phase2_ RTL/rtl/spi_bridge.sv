`timescale 1ns/1ps

module npu_spi_bridge (
  input  logic clk, rst_n,
  input  logic spi_cs_n_i, spi_sck_i, spi_mosi_i,
  output logic spi_miso_o, spi_miso_oe_o,
  output logic PSEL, PENABLE, PWRITE,
  output logic [31:0] PADDR, PWDATA,
  input  logic [31:0] PRDATA,
  input  logic PREADY, PSLVERR,
  output logic tcdm_req_o, tcdm_wen_o,
  output logic [31:0] tcdm_addr_o, tcdm_wdata_o,
  output logic [3:0] tcdm_be_o,
  input  logic tcdm_gnt_i, tcdm_rvalid_i, tcdm_error_i,
  input  logic [31:0] tcdm_rdata_i
);
  localparam logic [7:0] BUSY = 8'h01, DONE = 8'h02, ERROR = 8'h82;
  typedef enum logic [2:0] {IDLE, APB_SETUP, APB_ACCESS, T_REQ, T_WAIT} state_t;
  state_t state_q;
  (* ASYNC_REG = "TRUE" *) logic [1:0] cs_sync, sck_sync, mosi_sync;
  logic cs_prev, sck_prev, armed_q, frame_active_q;
  logic [79:0] rx_q, tx_q;
  logic [6:0] count_q;
  logic [7:0] status_q;
  logic [31:0] result_q, addr_q, data_q;
  logic [3:0] be_q;
  logic write_q;

  assign spi_miso_o = tx_q[79];

  assign spi_miso_oe_o = rst_n && !spi_cs_n_i;
  assign PSEL = state_q == APB_SETUP || state_q == APB_ACCESS;
  assign PENABLE = state_q == APB_ACCESS;
  assign PWRITE = write_q;
  assign PADDR = addr_q;
  assign PWDATA = data_q;
  assign tcdm_req_o = state_q == T_REQ;
  assign tcdm_wen_o = !write_q;
  assign tcdm_addr_o = addr_q;
  assign tcdm_wdata_o = data_q;
  assign tcdm_be_o = be_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin

      cs_sync <= 0; cs_prev <= 0; armed_q <= 0; frame_active_q <= 0;
      sck_sync <= 0; sck_prev <= 0; mosi_sync <= 0;
      rx_q <= 0; tx_q <= 0; count_q <= 0;
      status_q <= 0; result_q <= 0; addr_q <= 0; data_q <= 0;
      be_q <= 0; write_q <= 0; state_q <= IDLE;
    end else begin
      cs_sync <= {cs_sync[0], spi_cs_n_i};
      sck_sync <= {sck_sync[0], spi_sck_i};
      mosi_sync <= {mosi_sync[0], spi_mosi_i};
      cs_prev <= cs_sync[1];
      sck_prev <= sck_sync[1];
      if (cs_sync[1]) armed_q <= 1;

      if (armed_q && cs_prev && !cs_sync[1]) begin
        frame_active_q <= 1;
        rx_q <= 0; count_q <= 0;
        tx_q <= {status_q, result_q, 40'b0};
      end else if (frame_active_q && !cs_sync[1]) begin
        if (!sck_sync[1] && sck_prev) tx_q <= {tx_q[78:0], 1'b0};
        if (sck_sync[1] && !sck_prev) begin

          if (count_q < 81) count_q <= count_q + 1'b1;
          if (count_q < 80) rx_q <= {rx_q[78:0], mosi_sync[1]};
        end
      end

      if (!cs_prev && cs_sync[1]) begin
        frame_active_q <= 0;

        if (frame_active_q && count_q == 80 && state_q == IDLE && rx_q[79:72] != 0) begin
          addr_q <= rx_q[63:32]; data_q <= rx_q[31:0]; be_q <= rx_q[67:64];
          write_q <= rx_q[79:72] == 2 || rx_q[79:72] == 4;
          status_q <= BUSY; result_q <= 0;
          if (rx_q[79:72] > 4) begin
            status_q <= ERROR; result_q <= 1;
          end else if (rx_q[33:32] != 0) begin
            status_q <= ERROR; result_q <= 2;
          end else if (rx_q[71:68] != 0 || (rx_q[79:72] == 2 && rx_q[67:64] != 4'hf)) begin
            status_q <= ERROR; result_q <= 3;
          end else if (rx_q[79:72] == 1 || rx_q[79:72] == 2) begin
            state_q <= APB_SETUP;
          end else state_q <= T_REQ;
        end
      end

      case (state_q)
        APB_SETUP: state_q <= APB_ACCESS;
        APB_ACCESS: if (PREADY) begin
          result_q <= PSLVERR ? 32'd4 : (write_q ? 32'd0 : PRDATA);
          status_q <= PSLVERR ? ERROR : DONE;
          state_q <= IDLE;
        end
        T_REQ: if (tcdm_gnt_i) begin
          if (tcdm_rvalid_i) begin
            result_q <= tcdm_error_i ? 32'd4 : (write_q ? 32'd0 : tcdm_rdata_i);
            status_q <= tcdm_error_i ? ERROR : DONE;
            state_q <= IDLE;
          end else state_q <= T_WAIT;
        end
        T_WAIT: if (tcdm_rvalid_i) begin
          result_q <= tcdm_error_i ? 32'd4 : (write_q ? 32'd0 : tcdm_rdata_i);
          status_q <= tcdm_error_i ? ERROR : DONE;
          state_q <= IDLE;
        end
        default: ;
      endcase
    end
  end
endmodule
