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
