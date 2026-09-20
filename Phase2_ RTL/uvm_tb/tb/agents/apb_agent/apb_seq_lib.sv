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






