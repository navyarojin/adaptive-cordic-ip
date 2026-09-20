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
