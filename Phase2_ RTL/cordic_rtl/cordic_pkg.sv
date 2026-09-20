`ifndef CORDIC_PKG_SV
`define CORDIC_PKG_SV











package cordic_pkg;

  
  localparam int FRAC_BITS         = 14;
  localparam int INPUT_INT_BITS    = 5;   
  localparam int INTERNAL_INT_BITS = 4;   
  localparam int OUTPUT_INT_BITS   = 2;   

  localparam int INPUT_WIDTH    = INPUT_INT_BITS    + FRAC_BITS; 
  localparam int INTERNAL_WIDTH = INTERNAL_INT_BITS + FRAC_BITS; 
  localparam int OUTPUT_WIDTH   = OUTPUT_INT_BITS   + FRAC_BITS; 
  localparam int RESIDUAL_WIDTH = OUTPUT_WIDTH;

  
  localparam int MAX_ITER         = 16; 
  localparam int FULL_ITER        = 14; 
  localparam int DEFAULT_MIN_ITER = 6;  
  localparam int MIN_ITER_FLOOR   = 6;

  localparam int NUM_MAG_BINS  = 8;
  localparam int NUM_MAG_EDGES = NUM_MAG_BINS - 1;
  localparam int unsigned MAG_BIN_EDGES [0:NUM_MAG_EDGES-1] = '{
    1 << FRAC_BITS, 2 << FRAC_BITS, 3 << FRAC_BITS, 4 << FRAC_BITS,
    5 << FRAC_BITS, 6 << FRAC_BITS, 7 << FRAC_BITS
  };
  localparam int unsigned MAG_BIN_SEED_BUDGET [0:NUM_MAG_BINS-1] = '{
    14, 14, 13, 10, 8, 2, 1, 1
  };

  
  
  
  
  localparam int ROM_DEPTH   = 19;
  localparam int SHIFT_WIDTH = 5;               
  localparam int ITER_CNT_WIDTH = (MAX_ITER <= 1) ? 1 : $clog2(MAX_ITER + 1);

  function automatic logic [ITER_CNT_WIDTH-1:0] bounded_full_iter(
    input logic [7:0] requested,
    input logic [7:0] requested_min
  );
    int minimum;
    int full;
    minimum = (requested_min < MIN_ITER_FLOOR) ? MIN_ITER_FLOOR : requested_min;
    if (minimum > MAX_ITER) minimum = MAX_ITER;
    full = (requested < minimum) ? minimum : requested;
    if (full > MAX_ITER) full = MAX_ITER;
    return ITER_CNT_WIDTH'(full);
  endfunction

  
  typedef logic signed [INTERNAL_WIDTH-1:0] cordic_word_t;

  
  
  
  
  
  
  
  
  
  typedef struct packed {
    logic                              start;
    logic signed [INPUT_WIDTH-1:0]     x_in;
    logic [ITER_CNT_WIDTH-1:0]         iter_budget; 
    logic                              sample_mode; 
    logic                              sigmoid_mode;
  } ctrl_to_core_t;

  typedef struct packed {
    logic                              valid;
    logic signed [OUTPUT_WIDTH-1:0]    early_result;
    logic signed [OUTPUT_WIDTH-1:0]    full_result;
    logic [OUTPUT_WIDTH-1:0]           residual;    
    logic [ITER_CNT_WIDTH-1:0]         iter_used;
    logic                              overflow;
  } core_to_ctrl_t;

  typedef struct packed {
    logic [15:0] error_threshold;
    logic [7:0]  sample_rate;
    logic [7:0]  min_iter;
    logic [7:0]  max_iter;
    logic [7:0]  full_iter;
    logic [15:0] qualification_count;
    logic [15:0] violation_limit;
    logic [15:0] update_interval;
    logic        lut_freeze;
    logic        lut_reset;
    logic        enable;
    logic [1:0]  activation_mode;
  } csr_to_ctrl_t;

  typedef struct packed {
    logic [31:0] sample_count;
    logic [15:0] max_error;
    logic [31:0] fallback_count;
    logic        fault_flag;
    logic        fallback_flag;
    logic        ready_flag;
  } ctrl_to_csr_t;

endpackage : cordic_pkg

`endif 
