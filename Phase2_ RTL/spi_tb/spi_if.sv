`timescale 1ns/1ps
interface spi_host_if;
  logic cs_n = 1, sck = 0, mosi = 0;
  wire miso, miso_oe;
  time low_time = 67ns, high_time = 73ns;
  bit check_oe = 1;

  task automatic transfer(input logic [79:0] command, output logic [79:0] response,
      input int bits = 80);
    response = 0;
    sck = 0; cs_n = 0;
    for (int i = 0; i < bits; i++) begin
      mosi = i < 80 ? command[79-i] : 1'b0;
      #(low_time);
      if (check_oe && !miso_oe) $fatal(1,"MISO output enable missing while selected");
      sck = 1;
      response = {response[78:0], miso};
      #(high_time);
      sck = 0;
    end
    #(low_time);
    cs_n = 1; mosi = 0;
    #(high_time);
    if (miso_oe) $fatal(1,"MISO output enable did not clear");
  endtask

  task automatic access(input logic [7:0] op, input logic [31:0] addr, data,
      output logic [31:0] result, input bit expect_error = 0,
      input logic [7:0] mask = 8'h0f);
    logic [79:0] response;
    bit done;
    transfer({op,mask,addr,data},response);
    done = 0;
    for (int i = 0; i < 10; i++) begin
      transfer(80'b0,response);
      if (response[73]) begin
        done = 1;
        break;
      end
    end
    if (!done) $fatal(1,"SPI polling timeout op=%h addr=%h",op,addr);
    if (response[79:72] !== (expect_error ? 8'h82 : 8'h02))
      $fatal(1,"SPI status op=%h addr=%h got=%h",op,addr,response[79:72]);
    result = response[71:40];
  endtask
endinterface
