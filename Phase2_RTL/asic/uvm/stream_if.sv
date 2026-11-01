`timescale 1ns/1ps
interface stream_if(input logic clk);
  logic rst_n=0;
  logic cpu_en_i=0,cpu_we_i=0;
  logic [3:0] cpu_be_i=0;
  logic [11:0] cpu_addr_i=0;
  logic [31:0] cpu_wdata_i=0,cpu_rdata_o;
  logic ps_en_i=0;
  logic [3:0] ps_we_i=0;
  logic [15:0] ps_addr_i=0;
  logic [31:0] ps_wdata_i=0,ps_rdata_o;
  wire irq_o;
endinterface
