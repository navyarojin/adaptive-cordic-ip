`timescale 1ns/1ps
module stream_top;
  import uvm_pkg::*;
  import stream_uvm_pkg::*;
  logic clk=0;
  always #5 clk=~clk;
  stream_if bus(clk);
  stream_mmio #(.LANES(4)) dut(
    .clk,.rst_n(bus.rst_n),.cpu_en_i(bus.cpu_en_i),.cpu_we_i(bus.cpu_we_i),
    .cpu_be_i(bus.cpu_be_i),.cpu_addr_i(bus.cpu_addr_i),.cpu_wdata_i(bus.cpu_wdata_i),
    .cpu_rdata_o(bus.cpu_rdata_o),.ps_en_i(bus.ps_en_i),.ps_we_i(bus.ps_we_i),
    .ps_addr_i(bus.ps_addr_i),.ps_wdata_i(bus.ps_wdata_i),.ps_rdata_o(bus.ps_rdata_o),.irq_o(bus.irq_o));
  initial begin
    uvm_config_db#(virtual stream_if)::set(null,"*","vif",bus);
    run_test("stream_model_test");
  end
  initial begin #100000000; $fatal(1,"UVM watchdog expired"); end
endmodule
