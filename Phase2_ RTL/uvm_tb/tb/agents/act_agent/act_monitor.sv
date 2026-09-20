


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
