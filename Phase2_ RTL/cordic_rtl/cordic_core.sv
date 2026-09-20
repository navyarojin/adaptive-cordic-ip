`ifndef CORDIC_CORE_SV
`define CORDIC_CORE_SV












































module cordic_core
  import cordic_pkg::*;
(
  input  logic clk,
  input  logic rst_n,          

  input  ctrl_to_core_t ctrl_i,

  
  input  logic [ITER_CNT_WIDTH-1:0] full_iter_i,

  
  
  
  
  
  input  logic round_mode_en_i,

  output core_to_ctrl_t ctrl_o,

  
  output logic dbg_valid_o,
  output logic signed [INTERNAL_WIDTH-1:0] dbg_full_result_o,
  output logic dbg_overflow_o
);

  
  
  
  localparam logic signed [INPUT_WIDTH-1:0] SAT_THRESHOLD_FIXED = 19'sd85197;   
  localparam logic signed [INPUT_WIDTH-1:0] RANGE_THRESHOLD_FIXED = 19'sd16384; 
  localparam logic signed [OUTPUT_WIDTH-1:0] OUT_POS_SAT = 16'sd16383;          
  localparam logic signed [OUTPUT_WIDTH-1:0] OUT_NEG_SAT = -16'sd16384;

  typedef enum logic [3:0] {
    S_IDLE,
    S_SAT_BYPASS,
    S_RANGE_REDUCE,
    S_CORDIC_RUN,
    S_RECON_DIV0_START,
    S_RECON_DIV0_WAIT,
    S_RECON_LOOP_CHECK,
    S_RECON_MUL,
    S_RECON_DIV_START,
    S_RECON_DIV_WAIT,
    S_RECON_SAT,
    S_PHASE_ADVANCE,
    S_DONE
  } state_t;

  state_t state_q, state_n;

  
  logic signed [INPUT_WIDTH-1:0] rr_val_q;
  logic [3:0] k_q;
  logic rr_continue;
  cordic_word_t rr_shifted;

  
  cordic_word_t x_q, y_q, z_q;
  logic [ITER_CNT_WIDTH-1:0] step_q;
  logic [SHIFT_WIDTH-1:0] cordic_idx;
  cordic_word_t cordic_atanh_val;
  logic cordic_d_pos;
  cordic_word_t cordic_shifted_x, cordic_shifted_y;
  logic signed [INTERNAL_WIDTH+1:0] x_sum, y_sum, z_sum;
  cordic_word_t x_new, y_new, z_new;
  logic ov_x, ov_y, ov_z;
  logic cordic_overflow_sticky_q;

  cordic_word_t early_x_q, early_y_q, full_x_q, full_y_q;

  
  logic phase_q;              
  logic [3:0] j_q;            
  cordic_word_t t_q;
  cordic_word_t t_sq_q;
  logic mul_overflow;
  cordic_word_t mul_result;
  logic signed [OUTPUT_WIDTH-1:0] early_result_q, full_result_q;
  logic recon_overflow_sticky_q;

  
  logic div_start;
  logic signed [31:0] div_num;
  logic signed [17:0] div_den;
  logic div_busy, div_done, div_by_zero;
  logic signed [31:0] div_quotient;

  logic [ITER_CNT_WIDTH-1:0] run_len; 
  logic [ITER_CNT_WIDTH-1:0] iter_budget_q;
  logic [ITER_CNT_WIDTH-1:0] full_iter_q;
  logic sample_mode_q;
  logic sigmoid_mode_q;
  logic signed [INPUT_WIDTH-1:0] x_in_q;
  logic signed [INPUT_WIDTH-1:0] active_x_in;

  assign run_len = sample_mode_q ? full_iter_q : iter_budget_q;

  
  
  
  
  
  logic signed [31:0] early_y_ext, full_y_ext, t_ext;
  assign early_y_ext = early_y_q;
  assign full_y_ext  = full_y_q;
  assign t_ext       = t_q;

  
  
  
  
  
  
  
  
  
  
  
  
  logic signed [INPUT_WIDTH-1:0] x_in_halved;
  logic signed [INPUT_WIDTH-1:0] eff_x_in;
  
  
  
  
  
  
  
  
  
  assign active_x_in = (state_q == S_IDLE) ? ctrl_i.x_in : x_in_q;
  assign x_in_halved = round_mode_en_i
                        ? (($signed({active_x_in[INPUT_WIDTH-1], active_x_in}) + 20'sd1) >>> 1)
                        : (active_x_in >>> 1);
  assign eff_x_in = ((state_q == S_IDLE) ? ctrl_i.sigmoid_mode : sigmoid_mode_q)
                  ? x_in_halved : active_x_in;

  
  
  
  
  assign rr_continue = (rr_val_q > RANGE_THRESHOLD_FIXED) || (rr_val_q < -RANGE_THRESHOLD_FIXED);

  cordic_ashr u_rr_ashr (
    
    
    
    
    
    .val(cordic_word_t'(rr_val_q)), .shift(5'd1), .round_mode(round_mode_en_i),
    .result(rr_shifted)
  );

  
  
  
  cordic_iter_seq_rom u_seq (.step(step_q), .idx(cordic_idx));
  cordic_atanh_rom     u_rom (.idx(cordic_idx), .atanh_val(cordic_atanh_val));

  assign cordic_d_pos = (z_q >= 0);

  cordic_ashr u_ashr_x (.val(x_q), .shift(cordic_idx), .round_mode(round_mode_en_i), .result(cordic_shifted_x));
  cordic_ashr u_ashr_y (.val(y_q), .shift(cordic_idx), .round_mode(round_mode_en_i), .result(cordic_shifted_y));

  
  
  
  assign x_sum = cordic_d_pos ? (x_q + cordic_shifted_y) : (x_q - cordic_shifted_y);
  assign y_sum = cordic_d_pos ? (y_q + cordic_shifted_x) : (y_q - cordic_shifted_x);
  assign z_sum = cordic_d_pos ? (z_q - cordic_atanh_val) : (z_q + cordic_atanh_val);

  cordic_saturate u_sat_x (.val(x_sum), .val_sat(x_new), .overflow(ov_x));
  cordic_saturate u_sat_y (.val(y_sum), .val_sat(y_new), .overflow(ov_y));
  cordic_saturate u_sat_z (.val(z_sum), .val_sat(z_new), .overflow(ov_z));

  
  
  
  fx_mul_round u_mul (.a(t_q), .b(t_q), .result(mul_result), .overflow(mul_overflow));

  
  
  
  fx_signed_divider #(.NUM_WIDTH(32), .DEN_WIDTH(18)) u_div (
    .clk(clk), .rst_n(rst_n),
    .start(div_start), .numerator(div_num), .denominator(div_den),
    .busy(div_busy), .done(div_done), .quotient(div_quotient), .div_by_zero(div_by_zero)
  );

  
  
  
  always_comb begin
    state_n = state_q;
    unique case (state_q)
      S_IDLE: begin
        if (ctrl_i.start) begin
          if ((eff_x_in >= SAT_THRESHOLD_FIXED) || (eff_x_in <= -SAT_THRESHOLD_FIXED))
            state_n = S_SAT_BYPASS;
          else
            state_n = S_RANGE_REDUCE;
        end
      end
      S_SAT_BYPASS:      state_n = S_DONE;
      S_RANGE_REDUCE:    if (!rr_continue) state_n = S_CORDIC_RUN;
      S_CORDIC_RUN:      if (step_q == run_len - 1) state_n = S_RECON_DIV0_START;
      S_RECON_DIV0_START: begin
        if (!phase_q && early_x_q == 0)      state_n = S_RECON_LOOP_CHECK;
        else if (phase_q && full_x_q == 0)   state_n = S_RECON_LOOP_CHECK;
        else                                  state_n = S_RECON_DIV0_WAIT;
      end
      S_RECON_DIV0_WAIT: if (div_done) state_n = S_RECON_LOOP_CHECK;
      S_RECON_LOOP_CHECK: begin
        if (j_q == k_q) state_n = S_RECON_SAT;
        else             state_n = S_RECON_MUL;
      end
      S_RECON_MUL:        state_n = S_RECON_DIV_START;
      S_RECON_DIV_START:  state_n = S_RECON_DIV_WAIT;
      S_RECON_DIV_WAIT:   if (div_done) state_n = S_RECON_LOOP_CHECK;
      S_RECON_SAT:         state_n = S_PHASE_ADVANCE;
      S_PHASE_ADVANCE: begin
        if (!phase_q && sample_mode_q) state_n = S_RECON_DIV0_START;
        else                                 state_n = S_DONE;
      end
      S_DONE:              state_n = S_IDLE;
      default:              state_n = S_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      rr_val_q <= '0;
      k_q <= '0;
      x_q <= '0; y_q <= '0; z_q <= '0;
      step_q <= '0;
      cordic_overflow_sticky_q <= 1'b0;
      early_x_q <= '0; early_y_q <= '0;
      full_x_q  <= '0; full_y_q  <= '0;
      phase_q <= 1'b0;
      iter_budget_q <= '0;
      full_iter_q <= '0;
      sample_mode_q <= 1'b0;
      sigmoid_mode_q <= 1'b0;
      x_in_q <= '0;
      j_q <= '0;
      t_q <= '0;
      t_sq_q <= '0;
      early_result_q <= '0;
      full_result_q  <= '0;
      recon_overflow_sticky_q <= 1'b0;
      div_start <= 1'b0;
      div_num <= '0;
      div_den <= '0;
      ctrl_o <= '0;
      dbg_valid_o <= 1'b0;
      dbg_full_result_o <= '0;
      dbg_overflow_o <= 1'b0;
    end else begin
      state_q <= state_n;
      div_start <= 1'b0;
      ctrl_o.valid <= 1'b0;
      dbg_valid_o <= 1'b0;

      case (state_q)
        
        S_IDLE: begin
          if (ctrl_i.start) begin
            rr_val_q <= eff_x_in;
            iter_budget_q <= ctrl_i.iter_budget;
            full_iter_q <= full_iter_i;
            sample_mode_q <= ctrl_i.sample_mode;
            sigmoid_mode_q <= ctrl_i.sigmoid_mode;
            x_in_q <= ctrl_i.x_in;
            k_q <= '0;
            cordic_overflow_sticky_q <= 1'b0;
            recon_overflow_sticky_q <= 1'b0;
            phase_q <= 1'b0;
          end
        end

        
        S_SAT_BYPASS: begin
          logic signed [OUTPUT_WIDTH-1:0] tanh_sat_val;
          tanh_sat_val = (eff_x_in > 0) ? OUT_POS_SAT : OUT_NEG_SAT;
          k_q <= '0;
          if (!sigmoid_mode_q) begin
            early_result_q <= tanh_sat_val;
            full_result_q  <= tanh_sat_val;
          end else begin
            
            
            
            
            logic signed [INTERNAL_WIDTH-1:0] sig_sum, sig_biased, sig_shifted;
            logic signed [OUTPUT_WIDTH-1:0] sig_sat;
            sig_sum    = 18'(tanh_sat_val) + 18'sd16384;
            sig_biased = round_mode_en_i ? (sig_sum + 18'sd1) : sig_sum;
            sig_shifted = sig_biased >>> 1;
            if (sig_shifted > (cordic_word_t'(1) <<< (OUTPUT_WIDTH-1)) - 1)
              sig_sat = OUT_POS_SAT;
            else if (sig_shifted < -(cordic_word_t'(1) <<< (OUTPUT_WIDTH-1)))
              sig_sat = OUT_NEG_SAT;
            else
              sig_sat = sig_shifted[OUTPUT_WIDTH-1:0];
            early_result_q <= sig_sat;
            full_result_q  <= sig_sat;
          end
        end

        
        S_RANGE_REDUCE: begin
          if (rr_continue) begin
            rr_val_q <= rr_shifted; 
            k_q <= k_q + 1'b1;
          end else begin
            
            x_q <= cordic_word_t'(1 <<< FRAC_BITS);
            y_q <= '0;
            z_q <= cordic_word_t'(rr_val_q);
            step_q <= '0;
          end
        end

        
        S_CORDIC_RUN: begin
          x_q <= x_new;
          y_q <= y_new;
          z_q <= z_new;
          cordic_overflow_sticky_q <= cordic_overflow_sticky_q | ov_x | ov_y | ov_z;
          if (step_q == iter_budget_q - 1) begin
            early_x_q <= x_new;
            early_y_q <= y_new;
          end
          if (sample_mode_q && step_q == full_iter_q - 1) begin
            full_x_q <= x_new;
            full_y_q <= y_new;
          end
          if (step_q != run_len - 1) step_q <= step_q + 1'b1;
        end

        
        S_RECON_DIV0_START: begin
          j_q <= '0;
          if (!phase_q) begin
            if (early_x_q == 0) t_q <= '0;
            else begin
              
              div_num   <= early_y_ext <<< FRAC_BITS;
              div_den   <= early_x_q;
              div_start <= 1'b1;
            end
          end else begin
            if (full_x_q == 0) t_q <= '0;
            else begin
              div_num   <= full_y_ext <<< FRAC_BITS;
              div_den   <= full_x_q;
              div_start <= 1'b1;
            end
          end
        end

        S_RECON_DIV0_WAIT: begin
          if (div_done) begin
            t_q <= div_by_zero ? '0 : cordic_word_t'(div_quotient);
          end
        end

        
        S_RECON_LOOP_CHECK: ; 

        S_RECON_MUL: begin
          t_sq_q <= mul_result;
          recon_overflow_sticky_q <= recon_overflow_sticky_q | mul_overflow;
        end

        S_RECON_DIV_START: begin
          
          
          
          
          
          
          div_num <= (t_ext <<< 1) <<< FRAC_BITS;
          div_den <= (cordic_word_t'(1 <<< FRAC_BITS) + t_sq_q);
          div_start <= 1'b1;
        end

        S_RECON_DIV_WAIT: begin
          if (div_done) begin
            t_q <= div_by_zero ? '0 : cordic_word_t'(div_quotient);
            j_q <= j_q + 1'b1;
          end
        end

        
        S_RECON_SAT: begin
          logic signed [OUTPUT_WIDTH-1:0] t_sat;
          logic t_ov;
          if (t_q > (cordic_word_t'(1) <<< (OUTPUT_WIDTH-1)) - 1) begin
            t_sat = OUT_POS_SAT; t_ov = 1'b1;
          end else if (t_q < -(cordic_word_t'(1) <<< (OUTPUT_WIDTH-1))) begin
            t_sat = OUT_NEG_SAT; t_ov = 1'b1;
          end else begin
            t_sat = t_q[OUTPUT_WIDTH-1:0]; t_ov = 1'b0;
          end
          recon_overflow_sticky_q <= recon_overflow_sticky_q | t_ov;

          if (!sigmoid_mode_q) begin
            if (!phase_q) early_result_q <= t_sat;
            else          full_result_q  <= t_sat;
          end else begin
            
            
            
            
            
            logic signed [INTERNAL_WIDTH-1:0] sig_sum, sig_biased, sig_shifted;
            logic signed [OUTPUT_WIDTH-1:0] sig_sat;
            sig_sum    = 18'(t_sat) + 18'sd16384;
            sig_biased = round_mode_en_i ? (sig_sum + 18'sd1) : sig_sum;
            sig_shifted = sig_biased >>> 1;
            if (sig_shifted > (cordic_word_t'(1) <<< (OUTPUT_WIDTH-1)) - 1)
              sig_sat = OUT_POS_SAT;
            else if (sig_shifted < -(cordic_word_t'(1) <<< (OUTPUT_WIDTH-1)))
              sig_sat = OUT_NEG_SAT;
            else
              sig_sat = sig_shifted[OUTPUT_WIDTH-1:0];
            if (!phase_q) early_result_q <= sig_sat;
            else          full_result_q  <= sig_sat;
          end
        end

        S_PHASE_ADVANCE: begin
          if (!phase_q && sample_mode_q) begin
            phase_q <= 1'b1;
          end
        end

        
        S_DONE: begin
          ctrl_o.valid        <= 1'b1;
          ctrl_o.early_result <= early_result_q;
          ctrl_o.full_result  <= sample_mode_q ? full_result_q : early_result_q;
          ctrl_o.residual     <= sample_mode_q
                                 ? ((early_result_q > full_result_q)
                                    ? (early_result_q - full_result_q)
                                    : (full_result_q - early_result_q))
                                 : '0;
          ctrl_o.iter_used    <= iter_budget_q;
          ctrl_o.overflow     <= cordic_overflow_sticky_q | recon_overflow_sticky_q;

          dbg_valid_o        <= 1'b1;
          dbg_full_result_o  <= sample_mode_q ? cordic_word_t'(full_result_q) : cordic_word_t'(early_result_q);
          dbg_overflow_o     <= cordic_overflow_sticky_q | recon_overflow_sticky_q;
        end

        default: ;
      endcase
    end
  end

endmodule : cordic_core

`endif 
