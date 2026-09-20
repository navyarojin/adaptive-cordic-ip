




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
