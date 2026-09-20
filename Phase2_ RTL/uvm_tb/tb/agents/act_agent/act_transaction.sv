class act_transaction extends uvm_sequence_item;
  rand bit signed [cordic_pkg::INPUT_WIDTH-1:0] x;
       logic signed [cordic_pkg::OUTPUT_WIDTH-1:0] result;
       int unsigned iter_snapshot = 14;
       int unsigned full_snapshot = 14;
       int unsigned threshold_snapshot;
       bit sample_snapshot;
       bit               got_result;
       bit [1:0]         mode_snapshot;   
       bit               enable_snapshot; 

  `uvm_object_utils_begin(act_transaction)
    `uvm_field_int(x, UVM_ALL_ON)
    `uvm_field_int(result, UVM_ALL_ON)
    `uvm_field_int(mode_snapshot, UVM_ALL_ON)
    `uvm_field_int(enable_snapshot, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "act_transaction");
    super.new(name);
  endfunction
endclass : act_transaction
