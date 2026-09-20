



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
