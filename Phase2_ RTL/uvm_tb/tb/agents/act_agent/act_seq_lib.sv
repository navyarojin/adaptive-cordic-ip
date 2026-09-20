class act_single_seq extends uvm_sequence #(act_transaction);
  `uvm_object_utils(act_single_seq)
  rand bit signed [cordic_pkg::INPUT_WIDTH-1:0] x;

  function new(string name = "act_single_seq");
    super.new(name);
  endfunction

  task body();
    act_transaction tr = act_transaction::type_id::create("tr");
    start_item(tr);
    tr.x = x;
    finish_item(tr);
  endtask
endclass : act_single_seq

