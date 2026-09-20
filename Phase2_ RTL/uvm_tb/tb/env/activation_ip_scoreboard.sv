


















class activation_ip_scoreboard extends uvm_subscriber #(act_transaction);
  `uvm_component_utils(activation_ip_scoreboard)

  localparam int INPUT_WIDTH  = cordic_pkg::INPUT_WIDTH;
  localparam int OUTPUT_WIDTH = cordic_pkg::OUTPUT_WIDTH;
  localparam int FRAC_BITS    = 14;                 
  localparam real LSB         = 1.0 / (2.0 ** FRAC_BITS);

  
  
  
  
  int unsigned tanh_sigmoid_tolerance_ulp = 64;

  int unsigned n_checked   = 0;
  int unsigned n_mismatch  = 0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function real fx_to_real(bit signed [INPUT_WIDTH-1:0] v);
    return real'(v) / (2.0 ** FRAC_BITS);
  endfunction

  function real tanh_ref(real value);
    real e2x;
    e2x = $exp(2.0 * value);
    return (e2x - 1.0) / (e2x + 1.0);
  endfunction

  
  function bit signed [OUTPUT_WIDTH-1:0] bypass_result(bit signed [INPUT_WIDTH-1:0] x, bit [1:0] mode);
    logic signed [18:0] value;
    if (mode == 2'b10) begin 
      value = x[INPUT_WIDTH-1] ? '0 : x;
    end else begin           
      value = x;
    end
    if (value > 19'sd32767) return 16'sd32767;
    if (value < -19'sd32768) return -16'sd32768;
    return value[15:0];
  endfunction

  function void write(act_transaction t);
    real x_r, expected_r, got_r, err_lsb;
    bit signed [OUTPUT_WIDTH-1:0] expected_fx;
    int signed expected_early, expected_full, exact_expected;

    if (!t.got_result) begin
      `uvm_error("SB", $sformatf("x=%0d never got a response", t.x))
      return;
    end
    if (!t.enable_snapshot) begin
      `uvm_warning("SB", "response observed while dbg_enable_o was low at request time -- unexpected, check enable timing")
    end

    n_checked++;
    expected_early = activation_reference_pkg::activation_fixed(t.x, t.mode_snapshot, t.iter_snapshot);
    expected_full = activation_reference_pkg::activation_fixed(t.x, t.mode_snapshot, t.full_snapshot);
    exact_expected = expected_early;
    if (t.sample_snapshot && ((expected_early > expected_full) ?
        expected_early - expected_full : expected_full - expected_early) > t.threshold_snapshot)
      exact_expected = expected_full;
    if (t.result !== OUTPUT_WIDTH'(exact_expected)) begin
      n_mismatch++;
      `uvm_error("SB_EXACT", $sformatf("mode=%0d x=%0d iter=%0d expected=%0d got=%0d",
        t.mode_snapshot,t.x,t.iter_snapshot,exact_expected,t.result))
    end

    case (t.mode_snapshot)
      2'b10, 2'b11: begin 
        expected_fx = bypass_result(t.x, t.mode_snapshot);
        if (expected_fx !== t.result) begin
          n_mismatch++;
          `uvm_error("SB", $sformatf(
            "BYPASS mismatch mode=%0d x=%0d expected=%0d got=%0d",
            t.mode_snapshot, t.x, expected_fx, t.result))
        end
      end

      2'b00, 2'b01: begin 
        x_r = fx_to_real(t.x);
        expected_r = (t.mode_snapshot == 2'b00) ? tanh_ref(x_r)
                                                 : 0.5 * (1.0 + tanh_ref(x_r / 2.0));
        got_r   = real'(expected_full) / (2.0 ** FRAC_BITS);
        err_lsb = (got_r - expected_r) / LSB;
        if (err_lsb < 0) err_lsb = -err_lsb;

        if (t.full_snapshot >= 14 && err_lsb > real'(tanh_sigmoid_tolerance_ulp)) begin
          n_mismatch++;
          `uvm_error("SB", $sformatf(
            "%s error too large: x=%0d(%.5f) expected~=%.5f got=%.5f err=%.1f LSB (tol=%0d)",
            (t.mode_snapshot == 2'b00) ? "TANH" : "SIGMOID",
            t.x, x_r, expected_r, got_r, err_lsb, tanh_sigmoid_tolerance_ulp))
        end
      end

      default: `uvm_error("SB", $sformatf("unexpected mode_snapshot=%0d", t.mode_snapshot))
    endcase
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SB", $sformatf("scoreboard: %0d checked, %0d mismatched", n_checked, n_mismatch), UVM_LOW)
    if (n_mismatch > 0)
      `uvm_error("SB", $sformatf("%0d/%0d checks FAILED", n_mismatch, n_checked))
    if (n_checked == 0) `uvm_error("SB", "No activation results checked")
  endfunction

endclass : activation_ip_scoreboard
