`ifndef FX_SIGNED_DIVIDER_SV
`define FX_SIGNED_DIVIDER_SV

module fx_signed_divider #(
  parameter int NUM_WIDTH = 32,
  parameter int DEN_WIDTH = 18,
  parameter int BITS_PER_CYCLE = 4
)(
  input  logic                        clk,
  input  logic                        rst_n,

  input  logic                        start,
  input  logic signed [NUM_WIDTH-1:0] numerator,
  input  logic signed [DEN_WIDTH-1:0] denominator,

  output logic                        busy,
  output logic                        done,
  output logic signed [NUM_WIDTH-1:0] quotient,
  output logic                        div_by_zero
);

  localparam int CNT_WIDTH = $clog2(NUM_WIDTH + 1);

  typedef enum logic [1:0] {ST_IDLE, ST_RUN, ST_FIX, ST_DONE} state_t;
  state_t state_q, state_n;

  logic [NUM_WIDTH-1:0] num_mag_q;
  logic [DEN_WIDTH-1:0] den_mag_q;
  logic [NUM_WIDTH-1:0] quot_q;
  logic [DEN_WIDTH:0]   rem_q;
  logic result_sign_q;
  logic den_is_zero_q;
  logic [CNT_WIDTH-1:0] cnt_q;

  logic [NUM_WIDTH-1:0] num_next, quot_next;
  logic [DEN_WIDTH:0] rem_next;

  initial begin
    if (BITS_PER_CYCLE < 1 || BITS_PER_CYCLE > NUM_WIDTH)
      $fatal(1, "BITS_PER_CYCLE must be between 1 and NUM_WIDTH");
  end

  always_comb begin
    num_next = num_mag_q;
    quot_next = quot_q;
    rem_next = rem_q;
    for (int stage = 0; stage < BITS_PER_CYCLE; stage++) begin
      if (int'(cnt_q) + stage < NUM_WIDTH) begin
        rem_next = {rem_next[DEN_WIDTH-1:0], num_next[NUM_WIDTH-1]};
        num_next = num_next << 1;
        quot_next = quot_next << 1;
        if (rem_next >= {1'b0, den_mag_q}) begin
          rem_next = rem_next - {1'b0, den_mag_q};
          quot_next[0] = 1'b1;
        end
      end
    end
  end

  always_comb begin
    state_n = state_q;
    unique case (state_q)
      ST_IDLE: if (start) state_n = ST_RUN;
      ST_RUN:  if (int'(cnt_q) + BITS_PER_CYCLE >= NUM_WIDTH) state_n = ST_FIX;
      ST_FIX:  state_n = ST_DONE;
      ST_DONE: state_n = ST_IDLE;
      default: state_n = ST_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q       <= ST_IDLE;
      num_mag_q     <= '0;
      den_mag_q     <= '0;
      quot_q        <= '0;
      rem_q         <= '0;
      result_sign_q <= 1'b0;
      den_is_zero_q <= 1'b0;
      cnt_q         <= '0;
      done          <= 1'b0;
      quotient      <= '0;
      div_by_zero   <= 1'b0;
    end else begin
      state_q <= state_n;
      done    <= 1'b0;

      case (state_q)
        ST_IDLE: begin
          if (start) begin

            num_mag_q     <= numerator[NUM_WIDTH-1] ? (~numerator + 1'b1) : numerator;
            den_mag_q     <= denominator[DEN_WIDTH-1] ? (~denominator + 1'b1) : denominator;
            result_sign_q <= numerator[NUM_WIDTH-1] ^ denominator[DEN_WIDTH-1];
            den_is_zero_q <= (denominator == '0);
            quot_q        <= '0;
            rem_q         <= '0;
            cnt_q         <= '0;
          end
        end

        ST_RUN: begin

          rem_q <= rem_next;
          quot_q <= quot_next;
          num_mag_q <= num_next;
          cnt_q <= cnt_q + CNT_WIDTH'(BITS_PER_CYCLE);
        end

        ST_FIX: begin

          if ((rem_q << 1) >= {1'b0, den_mag_q}) begin
            quot_q <= quot_q + 1'b1;
          end
        end

        ST_DONE: begin
          done        <= 1'b1;
          div_by_zero <= den_is_zero_q;
          quotient    <= den_is_zero_q ? '0
                         : (result_sign_q ? (~quot_q + 1'b1) : quot_q);
        end

        default: ;
      endcase
    end
  end

  assign busy = (state_q != ST_IDLE);

endmodule : fx_signed_divider

`endif
