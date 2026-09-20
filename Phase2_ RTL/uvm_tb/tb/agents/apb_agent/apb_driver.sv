






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
