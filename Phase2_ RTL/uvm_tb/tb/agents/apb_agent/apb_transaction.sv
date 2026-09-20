



class apb_transaction extends uvm_sequence_item;

  rand bit         write;      
  rand bit [31:0]  addr;
  rand bit [31:0]  wdata;      
       bit [31:0]  rdata;      
       bit         slverr;

  `uvm_object_utils_begin(apb_transaction)
    `uvm_field_int(write,  UVM_ALL_ON)
    `uvm_field_int(addr,   UVM_ALL_ON)
    `uvm_field_int(wdata,  UVM_ALL_ON)
    `uvm_field_int(rdata,  UVM_ALL_ON)
    `uvm_field_int(slverr, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "apb_transaction");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("%s addr=0x%0h wdata=0x%0h rdata=0x%0h slverr=%0b",
                      write ? "WR" : "RD", addr, wdata, rdata, slverr);
  endfunction

endclass : apb_transaction
