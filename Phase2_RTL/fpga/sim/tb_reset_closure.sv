`timescale 1ns/1ps
module tb_reset_closure;
  logic clk=0,rst_n=0;
  always #20 clk=~clk;
  pynq_npu_soc dut (
    .clk,.rst_n,.stream_rdata_i(32'b0),.stream_irq_i(1'b0),
    .mailbox_rdata_i(32'b0),.stream_en_o(),.stream_we_o(),.stream_be_o(),
    .stream_addr_o(),.stream_wdata_o(),.mailbox_en_o(),.mailbox_we_o(),
    .mailbox_be_o(),.mailbox_addr_o(),.mailbox_wdata_o(),.test_status_o(),
    .test_detail_o(),.cycles_o(),.uart_tx_o(),.spi_cs_n_o(),.spi_sck_o(),
    .spi_mosi_o(),.spi_miso_o(),.npu_irq_o());
  task automatic wait_sleep;
    for (int cycle=0;cycle<1000;cycle++) begin
      @(negedge clk);
      if (dut.cpu.core_sleep_o) begin
        if (dut.cpu.core_i.id_stage_i.register_file_i.mem[5]!==32'd7)
          $fatal(1,"CPU did not execute boot instruction");
        return;
      end
    end
    $fatal(1,"CPU failed to enter WFI");
  endtask
  initial begin
    #1;
    dut.ram.mem['h400]=32'h00700293;
    dut.ram.mem['h401]=32'h10500073;
    dut.ram.mem['h402]=32'h0000006f;
    repeat(8) @(negedge clk);
    rst_n=1;
    for (int boot=0;boot<3;boot++) begin
      wait_sleep();
      #7; rst_n=0;
      #1;
      if (dut.cpu.core_i.id_stage_i.register_file_i.mem[5]!==32'd7)
        $fatal(1,"Functional register reset changed asynchronously");
      repeat(5) @(negedge clk);
      if (dut.cpu.core_i.id_stage_i.register_file_i.mem[5]!==32'b0)
        $fatal(1,"CPU gated clock blocked synchronous reset");
      if (dut.i_gnt || dut.d_gnt) $fatal(1,"Memory grant during reset");
      rst_n=1;
    end
    wait_sleep();
    $display("PASS FPGA reset closure: four boots, three off-edge resets from WFI, synchronous state clear and disabled RAM grants");
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1,"Reset closure timeout");
  end
endmodule
