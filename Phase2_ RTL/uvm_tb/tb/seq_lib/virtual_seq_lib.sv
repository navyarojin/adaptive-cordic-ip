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
