




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
