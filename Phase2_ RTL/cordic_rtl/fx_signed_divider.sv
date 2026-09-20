`ifndef FX_SIGNED_DIVIDER_SV
`define FX_SIGNED_DIVIDER_SV




























module fx_signed_divider #(
  parameter int NUM_WIDTH = 32,
  parameter int DEN_WIDTH = 18
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

  logic [DEN_WIDTH:0] rem_shifted;
  logic [DEN_WIDTH:0] rem_sub;
  logic               trial_ge;

  assign rem_shifted = {rem_q[DEN_WIDTH-1:0], num_mag_q[NUM_WIDTH-1]};
  assign rem_sub     = rem_shifted - {1'b0, den_mag_q};
  assign trial_ge    = ~rem_sub[DEN_WIDTH]; 

  always_comb begin
    state_n = state_q;
    unique case (state_q)
      ST_IDLE: if (start) state_n = ST_RUN;
      ST_RUN:  if (cnt_q == NUM_WIDTH-1) state_n = ST_FIX;
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
          
          
          
          
          if (trial_ge) begin
            rem_q  <= rem_sub[DEN_WIDTH-1:0];
            quot_q <= {quot_q[NUM_WIDTH-2:0], 1'b1};
          end else begin
            rem_q  <= rem_shifted[DEN_WIDTH-1:0];
            quot_q <= {quot_q[NUM_WIDTH-2:0], 1'b0};
          end
          num_mag_q <= num_mag_q << 1;
          cnt_q     <= cnt_q + 1'b1;
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
