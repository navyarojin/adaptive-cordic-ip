



































































import cordic_pkg::*;

module csr_apb (
  input  logic clk,
  input  logic rst_n,

  
  
  input  logic         PSEL,
  input  logic         PENABLE,
  input  logic         PWRITE,
  input  logic [31:0]  PADDR,
  input  logic [31:0]  PWDATA,
  output logic [31:0]  PRDATA,
  output logic         PREADY,
  output logic         PSLVERR,

  
  output csr_to_ctrl_t ctrl_o,
  input  ctrl_to_csr_t ctrl_i,

  
  output logic irq_o
);

  
  
  
  localparam logic [31:0] ADDR_CONTROL              = 32'h00;
  localparam logic [31:0] ADDR_STATUS                = 32'h04;
  localparam logic [31:0] ADDR_SAMPLE_COUNT          = 32'h08;
  localparam logic [31:0] ADDR_MAX_ERROR             = 32'h0C;
  localparam logic [31:0] ADDR_FALLBACK_COUNT        = 32'h10;
  localparam logic [31:0] ADDR_ERROR_THRESHOLD       = 32'h14;
  localparam logic [31:0] ADDR_SAMPLE_RATE           = 32'h18;
  localparam logic [31:0] ADDR_INTERRUPT_ENABLE      = 32'h1C;
  localparam logic [31:0] ADDR_MIN_ITER              = 32'h20;
  localparam logic [31:0] ADDR_MAX_ITER              = 32'h24;
  localparam logic [31:0] ADDR_FULL_ITER             = 32'h28;
  localparam logic [31:0] ADDR_QUALIFICATION_COUNT   = 32'h2C;
  localparam logic [31:0] ADDR_VIOLATION_LIMIT       = 32'h30;
  localparam logic [31:0] ADDR_UPDATE_INTERVAL       = 32'h34;
  localparam logic [31:0] ADDR_LUT_CONTROL           = 32'h38;

  
  
  
  localparam bit RO_WRITE_IS_ERROR = 1'b0;

  
  
  
  
  
  
  typedef enum logic [1:0] {ST_IDLE, ST_SETUP, ST_ACCESS} apb_state_e;
  apb_state_e state_q, state_d;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) state_q <= ST_IDLE;
    else        state_q <= state_d;
  end

  always_comb begin
    state_d = state_q;
    unique case (state_q)
      ST_IDLE:   state_d = PSEL ? ST_SETUP : ST_IDLE;
      ST_SETUP:  state_d = ST_ACCESS;              
      ST_ACCESS: state_d = PSEL ? (PENABLE ? ST_SETUP : ST_ACCESS) : ST_IDLE;
      default:   state_d = ST_IDLE;
    endcase
  end

  wire apb_access_fire = PSEL && PENABLE;

  
  
  
  
  logic [31:0] control_q;              
  logic [31:0] interrupt_enable_q;     
  logic [15:0] error_threshold_q;
  logic [7:0]  sample_rate_q;
  logic [7:0]  min_iter_q;
  logic [7:0]  max_iter_q;
  logic [7:0]  full_iter_q;
  logic [15:0] qualification_count_q;
  logic [15:0] violation_limit_q;
  logic [15:0] update_interval_q;
  logic [31:0] lut_control_q;          

  
  
  wire        enable_q       = control_q[0];
  wire [1:0]  mode_select_q  = control_q[2:1];   
  wire        confidence_req_q = control_q[3];   

  
  wire lut_reset_q  = apb_access_fire && PWRITE &&
                       (PADDR == ADDR_LUT_CONTROL) && PWDATA[0];
  wire lut_freeze_q = lut_control_q[1];

  
  
  
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      control_q             <= '0;
      interrupt_enable_q    <= '0;
      error_threshold_q     <= 16'h0001; 
                                          
                                          
      sample_rate_q          <= 8'd64;    
      min_iter_q             <= MIN_ITER_FLOOR;
      max_iter_q             <= FULL_ITER;
      full_iter_q            <= FULL_ITER;
      qualification_count_q <= '0;      
      violation_limit_q      <= '0;      
      update_interval_q      <= '0;      
      lut_control_q          <= '0;
    end else if (apb_access_fire && PWRITE) begin
      unique case (PADDR)
        ADDR_CONTROL:            control_q             <= PWDATA;
        ADDR_INTERRUPT_ENABLE:   interrupt_enable_q    <= PWDATA;
        ADDR_ERROR_THRESHOLD:    error_threshold_q     <= PWDATA[15:0];
        ADDR_SAMPLE_RATE:        sample_rate_q         <= PWDATA[7:0];
        ADDR_MIN_ITER:           min_iter_q            <= PWDATA[7:0];
        ADDR_MAX_ITER:           max_iter_q            <= PWDATA[7:0];
        ADDR_FULL_ITER:          full_iter_q           <= PWDATA[7:0];
        ADDR_QUALIFICATION_COUNT: qualification_count_q <= PWDATA[15:0];
        ADDR_VIOLATION_LIMIT:    violation_limit_q     <= PWDATA[15:0];
        ADDR_UPDATE_INTERVAL:    update_interval_q     <= PWDATA[15:0];
        ADDR_LUT_CONTROL:        lut_control_q         <= {PWDATA[31:1], 1'b0};
        
        
        
        default: ; 
      endcase
    end
  end

  
  
  
  
  wire [31:0] status_word = {29'b0, ctrl_i.fallback_flag, ctrl_i.fault_flag, ctrl_i.ready_flag};

  logic addr_hit;
  logic addr_is_ro;

  always_comb begin
    PRDATA     = 32'h0;
    addr_hit   = 1'b1;
    addr_is_ro = 1'b0;

    unique case (PADDR)
      ADDR_CONTROL:              PRDATA = control_q;
      ADDR_STATUS:               begin PRDATA = status_word;                         addr_is_ro = 1'b1; end
      ADDR_SAMPLE_COUNT:         begin PRDATA = ctrl_i.sample_count;                 addr_is_ro = 1'b1; end
      ADDR_MAX_ERROR:            begin PRDATA = {16'b0, ctrl_i.max_error};           addr_is_ro = 1'b1; end
      ADDR_FALLBACK_COUNT:       begin PRDATA = ctrl_i.fallback_count;               addr_is_ro = 1'b1; end
      ADDR_ERROR_THRESHOLD:      PRDATA = {16'b0, error_threshold_q};
      ADDR_SAMPLE_RATE:          PRDATA = {24'b0, sample_rate_q};
      ADDR_INTERRUPT_ENABLE:     PRDATA = interrupt_enable_q;
      ADDR_MIN_ITER:             PRDATA = {24'b0, min_iter_q};
      ADDR_MAX_ITER:             PRDATA = {24'b0, max_iter_q};
      ADDR_FULL_ITER:            PRDATA = {24'b0, full_iter_q};
      ADDR_QUALIFICATION_COUNT:  PRDATA = {16'b0, qualification_count_q};
      ADDR_VIOLATION_LIMIT:      PRDATA = {16'b0, violation_limit_q};
      ADDR_UPDATE_INTERVAL:      PRDATA = {16'b0, update_interval_q};
      ADDR_LUT_CONTROL:          PRDATA = lut_control_q;
      default: begin
        PRDATA   = 32'h0;
        addr_hit = 1'b0;
      end
    endcase
  end

  
  wire ro_write_violation = apb_access_fire && PWRITE && addr_is_ro && RO_WRITE_IS_ERROR;

  always_comb begin
    PREADY  = 1'b1;
    PSLVERR = apb_access_fire && (!addr_hit || ro_write_violation);
  end

  
  
  
  always_comb begin
    ctrl_o.error_threshold      = error_threshold_q;
    ctrl_o.sample_rate          = sample_rate_q;
    ctrl_o.min_iter             = min_iter_q;
    ctrl_o.max_iter             = max_iter_q;
    ctrl_o.full_iter            = full_iter_q;
    ctrl_o.qualification_count  = qualification_count_q;
    ctrl_o.violation_limit      = violation_limit_q;
    ctrl_o.update_interval      = update_interval_q;
    ctrl_o.lut_freeze           = lut_freeze_q;
    ctrl_o.lut_reset            = lut_reset_q;
    ctrl_o.enable               = enable_q;
    ctrl_o.activation_mode      = mode_select_q;
  end

  
  
  
  
  
  
  
  
  always_comb begin
    irq_o = |(interrupt_enable_q[2:0] &
              {ctrl_i.fallback_flag, ctrl_i.fault_flag, ctrl_i.ready_flag});
  end

endmodule : csr_apb
