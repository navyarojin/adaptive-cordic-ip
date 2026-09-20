



`timescale 1ns/1ps

module hvl_top;
  import uvm_pkg::*;
  import activation_ip_pkg::*;

  initial begin
    uvm_config_db#(virtual apb_if.DRIVER)::set(null, "uvm_test_top.env.apb_agt.driver",  "vif", hdl_top.u_apb_if);
    uvm_config_db#(virtual apb_if.MONITOR)::set(null, "uvm_test_top.env.apb_agt.monitor", "vif", hdl_top.u_apb_if);
    uvm_config_db#(virtual act_if.DRIVER)::set(null, "uvm_test_top.env.act_agt.driver",  "vif", hdl_top.u_act_if);
    uvm_config_db#(virtual act_if.MONITOR)::set(null, "uvm_test_top.env.act_agt.monitor", "vif", hdl_top.u_act_if);
    uvm_config_db#(virtual tcdm_if)::set(null, "uvm_test_top", "tcdm_vif", hdl_top.u_tcdm_if);

    run_test();
  end

endmodule : hvl_top
