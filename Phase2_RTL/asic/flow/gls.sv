`timescale 1ns/1ps
module gls_top;
  import uvm_pkg::*;
  import stream_uvm_pkg::*;
  logic clk=0;
  real period=40.0;
  string sdf_file;
  string sdf_corner="MAXIMUM";
  stream_if bus(clk);
  stream_mmio dut(
    .clk,.rst_n(bus.rst_n),.cpu_en_i(bus.cpu_en_i),.cpu_we_i(bus.cpu_we_i),
    .cpu_be_i(bus.cpu_be_i),.cpu_addr_i(bus.cpu_addr_i),.cpu_wdata_i(bus.cpu_wdata_i),
    .cpu_rdata_o(bus.cpu_rdata_o),.ps_en_i(bus.ps_en_i),.ps_we_i(bus.ps_we_i),
    .ps_addr_i(bus.ps_addr_i),.ps_wdata_i(bus.ps_wdata_i),.ps_rdata_o(bus.ps_rdata_o),.irq_o(bus.irq_o));
  initial begin
    if (!$value$plusargs("CLK_NS=%f",period) || period<=0) $fatal(1,"Missing valid CLK_NS");
    if (!$value$plusargs("SDF=%s",sdf_file)) $fatal(1,"Missing SDF file");
    if ($value$plusargs("CORNER=%s",sdf_corner)) begin end
    fork
      forever #(period/2.0) clk=~clk;
    join_none
    $sdf_annotate(sdf_file,dut,,"sdf.log",sdf_corner);
    uvm_config_db#(virtual stream_if)::set(null,"*","vif",bus);
    run_test("stream_model_test");
  end
  initial begin #100000000; $fatal(1,"GLS watchdog expired"); end
endmodule
