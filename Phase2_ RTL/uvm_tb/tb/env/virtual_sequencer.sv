class virtual_sequencer extends uvm_sequencer;
  `uvm_component_utils(virtual_sequencer)

  apb_sequencer apb_seqr;
  act_sequencer act_seqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass : virtual_sequencer
