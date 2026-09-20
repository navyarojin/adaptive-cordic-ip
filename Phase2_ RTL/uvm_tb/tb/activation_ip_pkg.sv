package activation_ip_pkg;
  import uvm_pkg::*;
  import activation_ip_csr_addrs::*;
  `include "uvm_macros.svh"

  `include "apb_transaction.sv"
  `include "apb_sequencer.sv"
  `include "apb_driver.sv"
  `include "apb_monitor.sv"
  `include "apb_agent.sv"
  `include "apb_seq_lib.sv"

  `include "act_transaction.sv"
  `include "act_sequencer.sv"
  `include "act_driver.sv"
  `include "act_monitor.sv"
  `include "act_agent.sv"
  `include "act_seq_lib.sv"

  `include "activation_ip_scoreboard.sv"
  `include "activation_ip_coverage.sv"
  `include "virtual_sequencer.sv"
  `include "activation_ip_env.sv"

  `include "virtual_seq_lib.sv"

  `include "coverage_closure_test.sv"
endpackage : activation_ip_pkg
