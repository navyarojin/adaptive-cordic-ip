





interface apb_if (input logic clk, input logic rst_n);

  logic         PSEL;
  logic         PENABLE;
  logic         PWRITE;
  logic [31:0]  PADDR;
  logic [31:0]  PWDATA;
  logic [31:0]  PRDATA;
  logic         PREADY;
  logic         PSLVERR;

  clocking drv_cb @(posedge clk);
    output PSEL, PENABLE, PWRITE, PADDR, PWDATA;
    input  PRDATA, PREADY, PSLVERR;
  endclocking

  clocking mon_cb @(posedge clk);
    input PSEL, PENABLE, PWRITE, PADDR, PWDATA, PRDATA, PREADY, PSLVERR;
  endclocking

  modport DRIVER (clocking drv_cb, input clk, rst_n);
  modport MONITOR(clocking mon_cb, input clk, rst_n);

endinterface : apb_if
