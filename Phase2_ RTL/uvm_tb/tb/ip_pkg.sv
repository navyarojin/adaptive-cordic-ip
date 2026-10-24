package activation_ip_pkg;
  import uvm_pkg::*;
  import activation_ip_csr_addrs::*;
  `include "uvm_macros.svh"

class apb_transaction extends uvm_sequence_item;

  rand bit         write;
  rand bit [31:0]  addr;
  rand bit [31:0]  wdata;
       bit [31:0]  rdata;
       bit         slverr;

  `uvm_object_utils_begin(apb_transaction)
    `uvm_field_int(write,  UVM_ALL_ON)
    `uvm_field_int(addr,   UVM_ALL_ON)
    `uvm_field_int(wdata,  UVM_ALL_ON)
    `uvm_field_int(rdata,  UVM_ALL_ON)
    `uvm_field_int(slverr, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "apb_transaction");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("%s addr=0x%0h wdata=0x%0h rdata=0x%0h slverr=%0b",
                      write ? "WR" : "RD", addr, wdata, rdata, slverr);
  endfunction

endclass : apb_transaction

typedef uvm_sequencer #(apb_transaction) apb_sequencer;

class apb_driver extends uvm_driver #(apb_transaction);
  `uvm_component_utils(apb_driver)

  virtual apb_if.DRIVER vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb_if.DRIVER)::get(this, "", "vif", vif))
      `uvm_fatal("APB_DRV", "virtual interface must be set for: vif")
  endfunction

  task run_phase(uvm_phase phase);

    vif.drv_cb.PSEL    <= 1'b0;
    vif.drv_cb.PENABLE <= 1'b0;
    vif.drv_cb.PWRITE  <= 1'b0;
    vif.drv_cb.PADDR   <= '0;
    vif.drv_cb.PWDATA  <= '0;

    wait (vif.rst_n === 1'b1);
    @(vif.drv_cb);

    forever begin
      apb_transaction tr;
      seq_item_port.get_next_item(tr);
      drive_transfer(tr);
      seq_item_port.item_done();
    end
  endtask

  task drive_transfer(apb_transaction tr);
    int unsigned waited;
    @(vif.drv_cb);

    vif.drv_cb.PADDR   <= tr.addr;
    vif.drv_cb.PWRITE  <= tr.write;
    vif.drv_cb.PWDATA  <= tr.write ? tr.wdata : '0;
    vif.drv_cb.PSEL    <= 1'b1;
    vif.drv_cb.PENABLE <= 1'b0;
    @(vif.drv_cb);

    vif.drv_cb.PENABLE <= 1'b1;
    @(vif.drv_cb);
    waited = 0;
    while (vif.drv_cb.PREADY !== 1'b1) begin
      @(vif.drv_cb);
      waited++;
      if (waited >= 1024) `uvm_fatal("APB_DRV", "APB response timeout")
    end

    tr.rdata  = vif.drv_cb.PRDATA;
    tr.slverr = vif.drv_cb.PSLVERR;

    vif.drv_cb.PSEL    <= 1'b0;
    vif.drv_cb.PENABLE <= 1'b0;
  endtask

endclass : apb_driver

class apb_monitor extends uvm_monitor;
  `uvm_component_utils(apb_monitor)

  virtual apb_if.MONITOR vif;
  uvm_analysis_port #(apb_transaction) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb_if.MONITOR)::get(this, "", "vif", vif))
      `uvm_fatal("APB_MON", "virtual interface must be set for: vif")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.PSEL && vif.mon_cb.PENABLE && vif.mon_cb.PREADY) begin
        apb_transaction tr = apb_transaction::type_id::create("tr");
        tr.write  = vif.mon_cb.PWRITE;
        tr.addr   = vif.mon_cb.PADDR;
        tr.wdata  = vif.mon_cb.PWDATA;
        tr.rdata  = vif.mon_cb.PRDATA;
        tr.slverr = vif.mon_cb.PSLVERR;
        `uvm_info("APB_MON", tr.convert2string(), UVM_HIGH)
        ap.write(tr);
      end
    end
  endtask

endclass : apb_monitor

class apb_agent extends uvm_agent;
  `uvm_component_utils(apb_agent)

  apb_sequencer sequencer;
  apb_driver    driver;
  apb_monitor   monitor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    monitor = apb_monitor::type_id::create("monitor", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sequencer = apb_sequencer::type_id::create("sequencer", this);
      driver    = apb_driver::type_id::create("driver", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction

endclass : apb_agent

class apb_reg_write_seq extends uvm_sequence #(apb_transaction);
  `uvm_object_utils(apb_reg_write_seq)

  rand bit [31:0] addr;
  rand bit [31:0] wdata;
  bit slverr;

  function new(string name = "apb_reg_write_seq");
    super.new(name);
  endfunction

  task body();
    apb_transaction tr = apb_transaction::type_id::create("tr");
    start_item(tr);
    tr.write = 1'b1;
    tr.addr  = addr;
    tr.wdata = wdata;
    finish_item(tr);
    slverr = tr.slverr;
  endtask
endclass : apb_reg_write_seq

class apb_reg_read_seq extends uvm_sequence #(apb_transaction);
  `uvm_object_utils(apb_reg_read_seq)

  rand bit [31:0] addr;
  bit [31:0]      rdata;
  bit             slverr;

  function new(string name = "apb_reg_read_seq");
    super.new(name);
  endfunction

  task body();
    apb_transaction tr = apb_transaction::type_id::create("tr");
    start_item(tr);
    tr.write = 1'b0;
    tr.addr  = addr;
    finish_item(tr);
    rdata  = tr.rdata;
    slverr = tr.slverr;
  endtask
endclass : apb_reg_read_seq

class apb_config_seq extends uvm_sequence #(apb_transaction);
  `uvm_object_utils(apb_config_seq)

  rand bit        enable;
  rand bit [1:0]  activation_mode;
  rand bit [15:0] error_threshold;
  rand bit [7:0]  sample_rate;
  rand bit [7:0]  min_iter;
  rand bit [7:0]  max_iter;
  rand bit [7:0]  full_iter;
  rand bit [15:0] qualification_count;
  rand bit [15:0] violation_limit;
  rand bit [15:0] update_interval;
  rand bit        lut_freeze;
  bit             lut_reset_pulse;

  constraint c_iter_order {
    min_iter inside {[6:16]};
    max_iter inside {[min_iter:16]};
    full_iter inside {[max_iter:16]};
  }
  constraint c_reasonable_rate { sample_rate inside {0, 1, 2, 4, 8, 16, 32, 64, 128}; }

  function new(string name = "apb_config_seq");
    super.new(name);
  endfunction

  task body();
    write_reg(CONTROL,             {28'b0, 1'b0, activation_mode, enable});
    write_reg(ERROR_THRESHOLD,     {16'b0, error_threshold});
    write_reg(SAMPLE_RATE,         {24'b0, sample_rate});
    write_reg(MIN_ITER,            {24'b0, min_iter});
    write_reg(MAX_ITER,            {24'b0, max_iter});
    write_reg(FULL_ITER,           {24'b0, full_iter});
    write_reg(QUALIFICATION_COUNT, {16'b0, qualification_count});
    write_reg(VIOLATION_LIMIT,     {16'b0, violation_limit});
    write_reg(UPDATE_INTERVAL,     {16'b0, update_interval});
    write_reg(LUT_CONTROL,         {29'b0, 1'b0, lut_freeze, lut_reset_pulse});
  endtask

  task write_reg(bit [31:0] a, bit [31:0] d);
    apb_reg_write_seq wr = apb_reg_write_seq::type_id::create("wr");
    wr.addr  = a;
    wr.wdata = d;
    wr.start(m_sequencer, this);
    if (wr.slverr) `uvm_error("APB_CFG", $sformatf("Write rejected at address %h",a))
  endtask
endclass : apb_config_seq

class act_transaction extends uvm_sequence_item;
  rand bit signed [cordic_pkg::INPUT_WIDTH-1:0] x;
       logic signed [cordic_pkg::OUTPUT_WIDTH-1:0] result;
       int unsigned iter_snapshot = 14;
       int unsigned full_snapshot = 14;
       int unsigned threshold_snapshot;
       bit sample_snapshot;
       bit               got_result;
       bit [1:0]         mode_snapshot;
       bit               enable_snapshot;

  `uvm_object_utils_begin(act_transaction)
    `uvm_field_int(x, UVM_ALL_ON)
    `uvm_field_int(result, UVM_ALL_ON)
    `uvm_field_int(mode_snapshot, UVM_ALL_ON)
    `uvm_field_int(enable_snapshot, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "act_transaction");
    super.new(name);
  endfunction
endclass : act_transaction

typedef uvm_sequencer #(act_transaction) act_sequencer;

class act_driver extends uvm_driver #(act_transaction);
  `uvm_component_utils(act_driver)

  virtual act_if.DRIVER vif;
  int unsigned timeout_cycles = 1024;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual act_if.DRIVER)::get(this, "", "vif", vif))
      `uvm_fatal("ACT_DRV", "virtual interface must be set for: vif")
  endfunction

  task run_phase(uvm_phase phase);
    vif.drv_cb.x_valid_i       <= 1'b0;
    vif.drv_cb.x_i             <= '0;
    vif.drv_cb.round_mode_en_i <= 1'b1;
    wait (vif.rst_n === 1'b1);
    @(vif.drv_cb);

    forever begin
      act_transaction tr;
      int unsigned n;
      bit          got;
      bit          acknowledged;
      seq_item_port.get_next_item(tr);
      @(vif.drv_cb);
      n = 0;
      while (vif.drv_cb.ready_i !== 1'b1) begin
        @(vif.drv_cb);
        n++;
        if (n >= timeout_cycles) `uvm_fatal("ACT_DRV", "Activation ready timeout")
      end

      vif.drv_cb.x_i       <= tr.x;
      vif.drv_cb.x_valid_i <= 1'b1;
      @(vif.drv_cb);
      vif.drv_cb.x_valid_i <= 1'b0;

      got = 1'b0;
      acknowledged = 1'b0;
      tr.got_result = 1'b0;
      for (n = 0; n < timeout_cycles && !got; n++) begin
        if (vif.drv_cb.request_ack_i === 1'b1) begin
          acknowledged = 1'b1;
          if (vif.drv_cb.request_error_i !== 1'b0)
            `uvm_fatal("ACT_REJECT", $sformatf("Activation request rejected, x=%0d",tr.x))
        end
        if (vif.drv_cb.result_valid_o) begin
          tr.result     = vif.drv_cb.result_o;
          tr.got_result = 1'b1;
          got = 1'b1;
        end else
          @(vif.drv_cb);
      end
      if (!got)
        `uvm_fatal("ACT_DRV", $sformatf("timeout waiting for result_valid_o, x=%0d acknowledged=%0b ready=%0b cycles=%0d",
          tr.x,acknowledged,vif.drv_cb.ready_i,timeout_cycles))

      seq_item_port.item_done();
    end
  endtask
endclass : act_driver

class act_monitor extends uvm_monitor;
  `uvm_component_utils(act_monitor)

  virtual act_if.MONITOR vif;
  uvm_analysis_port #(act_transaction) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual act_if.MONITOR)::get(this, "", "vif", vif))
      `uvm_fatal("ACT_MON", "virtual interface must be set for: vif")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      act_transaction tr;
      @(vif.mon_cb);
      if (vif.mon_cb.x_valid_i) begin
        tr = act_transaction::type_id::create("tr");
        tr.x               = vif.mon_cb.x_i;
        tr.mode_snapshot   = vif.mon_cb.dbg_activation_mode_o;
        tr.enable_snapshot = vif.mon_cb.dbg_enable_o;
        tr.got_result      = 1'b0;
        tr.threshold_snapshot = vif.mon_cb.dbg_error_threshold_o;
        tr.full_snapshot = vif.mon_cb.dbg_full_iter;

        for (int unsigned cycles = 0; cycles < 1024; cycles++) begin
          if (vif.mon_cb.dbg_core_start_o) begin
            tr.iter_snapshot = vif.mon_cb.dbg_iter_budget_o;
            tr.sample_snapshot = vif.mon_cb.dbg_sample_mode_o;
          end
          if (vif.mon_cb.result_valid_o) begin
            tr.result     = vif.mon_cb.result_o;
            tr.got_result = 1'b1;
            break;
          end
          @(vif.mon_cb);
        end

        `uvm_info("ACT_MON", $sformatf("x=%0d mode=%0d result=%0d",
                  tr.x, tr.mode_snapshot, tr.result), UVM_HIGH)
        ap.write(tr);
      end
    end
  endtask
endclass : act_monitor

class act_agent extends uvm_agent;
  `uvm_component_utils(act_agent)

  act_sequencer sequencer;
  act_driver    driver;
  act_monitor   monitor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    monitor = act_monitor::type_id::create("monitor", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sequencer = act_sequencer::type_id::create("sequencer", this);
      driver    = act_driver::type_id::create("driver", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass : act_agent

class act_single_seq extends uvm_sequence #(act_transaction);
  `uvm_object_utils(act_single_seq)
  rand bit signed [cordic_pkg::INPUT_WIDTH-1:0] x;

  function new(string name = "act_single_seq");
    super.new(name);
  endfunction

  task body();
    act_transaction tr = act_transaction::type_id::create("tr");
    start_item(tr);
    tr.x = x;
    finish_item(tr);
  endtask
endclass : act_single_seq

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

class activation_ip_coverage extends uvm_subscriber #(act_transaction);
  `uvm_component_utils(activation_ip_coverage)

  act_transaction tr;

  covergroup cg;
    option.per_instance = 1;

    cp_mode: coverpoint tr.mode_snapshot {
      bins tanh    = {2'b00};
      bins sigmoid = {2'b01};
      bins relu    = {2'b10};
      bins linear  = {2'b11};
    }

    cp_x_range: coverpoint tr.x {
      bins big_neg   = {[-262144:-65537]};
      bins mid_neg   = {[-65536:-16385]};
      bins small_neg = {[-16384:-1]};
      bins zero      = {0};
      bins small_pos = {[1:16384]};
      bins mid_pos   = {[16385:65536]};
      bins big_pos   = {[65537:262143]};
    }

    cp_mode_x: cross cp_mode, cp_x_range;
    cp_magnitude: coverpoint ((tr.x < 0 ? -int'(tr.x) : int'(tr.x)) / 16384) {
      bins magnitude[7] = {[0:6]};
      bins tail = {[7:16]};
    }
    cp_mode_magnitude: cross cp_mode, cp_magnitude;
    cp_sample: coverpoint tr.sample_snapshot iff (tr.mode_snapshot < 2) {
      bins early_only = {0};
      bins qualified = {1};
    }

  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg = new();
  endfunction

  function void write(act_transaction t);
    tr = t;
    if (t.got_result)
      cg.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf("functional coverage: %.2f%%", cg.get_coverage()), UVM_LOW)
    if (cg.get_coverage() < 100.0) `uvm_error("COV", "Activation coverage is below 100%")
    `uvm_info("COV", $sformatf("mode: %.2f%%, input range: %.2f%%, mode x input range: %.2f%%",
              cg.cp_mode.get_coverage(), cg.cp_x_range.get_coverage(), cg.cp_mode_x.get_coverage()), UVM_LOW)
  endfunction

endclass : activation_ip_coverage

class virtual_sequencer extends uvm_sequencer;
  `uvm_component_utils(virtual_sequencer)

  apb_sequencer apb_seqr;
  act_sequencer act_seqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass : virtual_sequencer

class activation_ip_env extends uvm_env;
  `uvm_component_utils(activation_ip_env)

  apb_agent               apb_agt;
  act_agent                act_agt;
  activation_ip_scoreboard sb;
  activation_ip_coverage   cov;
  virtual_sequencer        vseqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_agt = apb_agent::type_id::create("apb_agt", this);
    act_agt = act_agent::type_id::create("act_agt", this);
    sb      = activation_ip_scoreboard::type_id::create("sb", this);
    cov     = activation_ip_coverage::type_id::create("cov", this);
    vseqr   = virtual_sequencer::type_id::create("vseqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    act_agt.monitor.ap.connect(sb.analysis_export);
    act_agt.monitor.ap.connect(cov.analysis_export);
    vseqr.apb_seqr = apb_agt.sequencer;
    vseqr.act_seqr = act_agt.sequencer;
  endfunction

endclass : activation_ip_env

class base_vseq extends uvm_sequence;
  `uvm_object_utils(base_vseq)
  `uvm_declare_p_sequencer(virtual_sequencer)

  function new(string name = "base_vseq");
    super.new(name);
  endfunction
endclass : base_vseq

class reset_config_vseq extends base_vseq;
  `uvm_object_utils(reset_config_vseq)
  rand bit [1:0] mode = 2'b00;
  rand bit [15:0] error_threshold = 16'h0200;
  rand bit [7:0] sample_rate = 8'd4;

  function new(string name = "reset_config_vseq");
    super.new(name);
  endfunction

  task body();
    apb_config_seq cfg = apb_config_seq::type_id::create("cfg");
    cfg.enable              = 1'b1;
    cfg.activation_mode     = mode;
    cfg.error_threshold     = error_threshold;
    cfg.sample_rate         = sample_rate;
    cfg.min_iter            = 8'd8;
    cfg.max_iter            = 8'd14;
    cfg.full_iter           = 8'd14;
    cfg.qualification_count = 16'd8;
    cfg.violation_limit     = 16'd3;
    cfg.update_interval     = 16'd16;
    cfg.lut_freeze          = 1'b0;
    cfg.lut_reset_pulse     = 1'b0;
    cfg.start(p_sequencer.apb_seqr);
  endtask
endclass : reset_config_vseq

class coverage_closure_vseq extends base_vseq;
  `uvm_object_utils(coverage_closure_vseq)

  function new(string name = "coverage_closure_vseq");
    super.new(name);
  endfunction

  task body();
    bit [1:0] modes[4] = '{2'b00, 2'b01, 2'b10, 2'b11};
    int signed representatives[7] = '{-131072, -32768, -8192, 0, 8192, 32768, 131072};
    foreach (modes[i]) begin
      reset_config_vseq cfg = reset_config_vseq::type_id::create($sformatf("cfg_mode_%0d", i));
      apb_reg_read_seq rd = apb_reg_read_seq::type_id::create($sformatf("rd_mode_%0d", i));
      cfg.mode = modes[i];
      cfg.sample_rate = 8'd1;
      cfg.start(p_sequencer);
      rd.addr = CONTROL;
      rd.start(p_sequencer.apb_seqr);
      if (rd.rdata[2:0] !== {1'b0, modes[i], 1'b1})
        `uvm_error("COV_CFG", $sformatf("CONTROL readback mismatch for mode %0d: 0x%08h", modes[i], rd.rdata))
      foreach (representatives[j]) begin
        act_single_seq one = act_single_seq::type_id::create($sformatf("mode_%0d_range_%0d", i, j));
        one.x = cordic_pkg::INPUT_WIDTH'(representatives[j]);
        one.start(p_sequencer.act_seqr);
      end
      for (int b = 0; b < 8; b++) begin
        act_single_seq one = act_single_seq::type_id::create("magnitude");
        one.x = cordic_pkg::INPUT_WIDTH'(b*16384 + 8192);
        one.start(p_sequencer.act_seqr);
      end
    end
  endtask
endclass : coverage_closure_vseq

class coverage_closure_test extends uvm_test;
  `uvm_component_utils(coverage_closure_test)
  activation_ip_env env;
  virtual tcdm_if bus;
  int npu_checks = 0;
  int observed_mode, observed_pattern, observed_feature;

  covergroup project_cg;
    option.per_instance = 1;
    cp_feature: coverpoint observed_feature {
      bins csr_readback = {0};
      bins invalid_address = {1};
      bins byte_enable = {2};
      bins full_fallback = {3};
      bins lut_decrease = {4};
      bins lut_freeze = {5};
      bins lut_reset = {6};
      bins sample_schedule = {7};
      bins iteration_clamp = {8};
      bins interrupt_clear = {9};
      bins disabled_start = {10};
      bins reset_busy = {11};
    }
  endgroup

  covergroup npu_cg;
    option.per_instance = 1;
    cp_mode: coverpoint observed_mode { bins modes[] = {[0:3]}; }
    cp_pattern: coverpoint observed_pattern {
      bins zero = {0}; bins dense = {1}; bins sparse_signed = {2}; bins extremes = {3};
    }
    cp_mode_pattern: cross cp_mode, cp_pattern;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name,parent);
    project_cg = new();
    npu_cg = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = activation_ip_env::type_id::create("env",this);
    if (!uvm_config_db#(virtual tcdm_if)::get(this,"","tcdm_vif",bus))
      `uvm_fatal("PROJECT","Missing TCDM interface")
  endfunction

  task apb_write(bit [31:0] address, data);
    apb_reg_write_seq seq = apb_reg_write_seq::type_id::create("write");
    seq.addr = address;
    seq.wdata = data;
    seq.start(env.apb_agt.sequencer);
    if (seq.slverr) `uvm_error("APB", $sformatf("Write rejected at address %h",address))
  endtask

  task apb_read(bit [31:0] address, output bit [31:0] data, input bit expect_error = 0);
    apb_reg_read_seq seq = apb_reg_read_seq::type_id::create("read");
    seq.addr = address;
    seq.start(env.apb_agt.sequencer);
    data = seq.rdata;
    if (seq.slverr != expect_error) `uvm_error("APB","Unexpected APB error response")
  endtask

  task access_bus(bit write, bit [31:0] address, data, output logic [31:0] response,
      input bit expect_error = 0, input bit [3:0] be = 4'hf);
    logic failed;
    bus.transfer(write,address,data,response,failed,be);
    if (failed !== expect_error) `uvm_error("TCDM",$sformatf("address=%h error=%b expected=%b",address,failed,expect_error))
  endtask

  task mark_feature(int feature);
    observed_feature = feature;
    project_cg.sample();
  endtask

  task configure(int mode, int minimum = 14, int maximum = 14, int full = 14,
      int threshold = 512, int sampling = 1, int qualification = 1, int violations = 1);
    `uvm_info("CONFIG",$sformatf("mode=%0d min=%0d max=%0d full=%0d threshold=%0d sampling=%0d",
      mode,minimum,maximum,full,threshold,sampling),UVM_MEDIUM)
    apb_write('h00,0);
    apb_write('h14,threshold);
    apb_write('h18,sampling);
    apb_write('h20,minimum);
    apb_write('h24,maximum);
    apb_write('h28,full);
    apb_write('h2c,qualification);
    apb_write('h30,violations);
    apb_write('h34,0);
    apb_write('h38,1);
    apb_write('h1c,0);
    apb_write('h00,(mode << 1) | 1);
  endtask

  task send_activation(int signed x);
    act_single_seq seq = act_single_seq::type_id::create("activation");
    seq.x = cordic_pkg::INPUT_WIDTH'(x);
    seq.start(env.act_agt.sequencer);
    repeat (2) @(negedge bus.clk);
  endtask

  task adaptive_checks();
    bit [31:0] before_count, after_count, status;
    int signed violating_x;
    configure(0,6,10,14,0);
    violating_x = 0;
    for (int x = 100; x < 16000; x += 73)
      if (activation_reference_pkg::activation_fixed(x,0,10) !=
          activation_reference_pkg::activation_fixed(x,0,14)) begin
        violating_x = x;
        break;
      end
    if (violating_x == 0) `uvm_fatal("REFERENCE","No fallback stimulus found")
    apb_read('h10,before_count);
    send_activation(violating_x);
    apb_read('h10,after_count);
    apb_read('h04,status);
    if (after_count != before_count+1 || !status[2]) `uvm_error("FALLBACK","Fallback telemetry mismatch")
    send_activation(violating_x);
    if (bus.last_budget != 14) `uvm_error("FALLBACK","Forced full iteration was capped by max_iter")
    mark_feature(3);

    configure(0,6,14,14,65535);
    send_activation(8192);
    send_activation(8192);
    if (bus.last_budget != 13) `uvm_error("LUT","Qualified budget did not decrease")
    mark_feature(4);
    apb_write('h38,3);
    send_activation(8192);
    send_activation(8192);
    if (bus.last_budget != 14) `uvm_error("LUT","Frozen LUT changed")
    mark_feature(5);
    apb_write('h38,1);
    send_activation(8192);
    if (bus.last_budget != 14) `uvm_error("LUT","LUT reset did not restore seed")
    mark_feature(6);

    configure(0,14,14,14,512,2);
    apb_read('h08,before_count);
    send_activation(8192);
    if (bus.last_sample) `uvm_error("SAMPLE","First request should be unsampled")
    send_activation(8192);
    if (!bus.last_sample) `uvm_error("SAMPLE","Second request should be sampled")
    apb_read('h08,after_count);
    if (after_count != before_count+1) `uvm_error("SAMPLE","Sample counter mismatch")
    mark_feature(7);

    configure(0,0,255,255);
    send_activation(8192);
    configure(0,255,0,0);
    send_activation(8192);
    if (bus.last_budget != 16) `uvm_error("GUARDRAIL","Invalid iteration settings were not clamped")
    mark_feature(8);
    configure(0);
  endtask

  task npu_case(int mode, int pattern);
    int signed weights[16], activations[4], sum, expected, quantized;
    int shift;
    logic [31:0] response;
    configure(mode);
    bus.active = 1;
    shift = pattern == 3 ? 4 : 0;
    for (int i = 0; i < 16; i++) begin
      weights[i] = pattern == 3 ? ((i%2) ? -128 : 127) : (i%7)-3;
      access_bus(1,i*4,weights[i],response);
    end
    for (int i = 0; i < 4; i++) begin
      case (pattern)
        0: activations[i] = 0;
        1: activations[i] = i+1;
        2: activations[i] = i%2 ? -(i+1) : 0;
        3: activations[i] = i%2 ? -128 : 127;
      endcase
      access_bus(1,'h40+i*4,activations[i],response);
    end
    access_bus(1,'h104,shift,response);
    access_bus(1,'h108,1,response);
    access_bus(1,'h100,1,response);
    for (int cycles = 0; cycles < 8192; cycles++) begin
      access_bus(0,'h100,0,response);
      if (response[1]) break;
      if (cycles == 8191) `uvm_fatal("NPU","Completion timeout")
    end
    for (int r = 0; r < 4; r++) begin
      sum = 0;
      for (int c = 0; c < 4; c++) sum += weights[r*4+c]*activations[c];
      access_bus(0,'h90+r*4,0,response);
      if ($signed(response) !== sum) `uvm_error("NPU",$sformatf("Row %0d MAC expected=%0d got=%0d",r,sum,$signed(response)))
      quantized = activation_reference_pkg::sat(sum >>> shift,19);
      expected = activation_reference_pkg::activation_fixed(quantized,mode,14);
      access_bus(0,'h80+r*4,0,response);
      if ($signed(response) !== expected) `uvm_error("NPU",$sformatf("Row %0d activation expected=%0d got=%0d",r,expected,$signed(response)))
      npu_checks++;
    end
    if (bus.irq !== 1'b1) `uvm_error("IRQ","Completion interrupt absent")
    access_bus(1,'h100,2,response);
    if (bus.irq !== 1'b0) `uvm_error("IRQ","Completion interrupt did not clear")
    mark_feature(9);
    observed_mode = mode;
    observed_pattern = pattern;
    npu_cg.sample();
    bus.active = 0;
  endtask

  task interface_checks();
    bit [31:0] value;
    logic [31:0] response;
    configure(0);
    apb_read('h14,value);
    if (value != 512) `uvm_error("CSR","Threshold readback mismatch")
    apb_read('h28,value);
    if (value != 14) `uvm_error("CSR","Full iteration readback mismatch")
    mark_feature(0);
    apb_read('hfc,value,1);
    bus.active = 1;
    access_bus(0,'hffc,0,response,1);
    access_bus(0,1,0,response,1);
    mark_feature(1);
    access_bus(1,0,'h55,response);
    access_bus(1,0,'haa,response,0,4'b1110);
    access_bus(0,0,0,response);
    if (response != 'h55) `uvm_error("TCDM","Byte enable did not protect weight")
    mark_feature(2);
    apb_write('h00,0);
    access_bus(1,'h100,1,response,1);
    mark_feature(10);
    configure(0);
    access_bus(1,'h100,1,response);
    @(negedge bus.clk);
    bus.reset_request = 1;
    repeat (4) @(negedge bus.clk);
    bus.reset_request = 0;
    repeat (2) @(negedge bus.clk);
    access_bus(0,'h100,0,response);
    if (response != 0) `uvm_error("RESET","Busy or done remained set after reset")
    access_bus(0,0,0,response);
    if (response != 0) `uvm_error("RESET","Weight buffer not reset")
    apb_read('h00,value);
    if (value != 0) `uvm_error("RESET","Control register not reset")
    mark_feature(11);
    bus.active = 0;
  endtask

  task run_phase(uvm_phase phase);
    coverage_closure_vseq seq = coverage_closure_vseq::type_id::create("seq");
    phase.raise_objection(this);
    wait(bus.rst_n);
    if ($test$plusargs("WAVE_MODE")) npu_case(3,2);
    do begin
      seq.start(env.vseqr);
      adaptive_checks();
      for (int mode = 0; mode < 4; mode++)
        for (int pattern = 0; pattern < 4; pattern++)
          npu_case(mode,pattern);
      interface_checks();
    end while ($test$plusargs("WAVE_MODE"));
    repeat (5) @(posedge bus.clk);
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info("PROJECT",$sformatf("Project features: %.2f%%, NPU coverage: %.2f%%, NPU outputs checked: %0d",
      project_cg.get_inst_coverage(),npu_cg.get_inst_coverage(),npu_checks),UVM_LOW)
    if (project_cg.get_inst_coverage() < 100.0 || npu_cg.get_inst_coverage() < 100.0 || npu_checks < 64)
      `uvm_error("PROJECT","Project coverage closure incomplete")
  endfunction
endclass

endpackage : activation_ip_pkg
