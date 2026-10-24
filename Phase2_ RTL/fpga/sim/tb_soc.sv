`timescale 1ns/1ps
module tb_pynq_soc;
  logic clk=0, rst_n=0;
  always #20 clk=~clk;
  wire [31:0] status, detail, cycles;
  wire cs_n, sck, mosi, miso, irq, uart;
  pynq_npu_soc dut (.clk, .rst_n, .test_status_o(status), .test_detail_o(detail),
    .cycles_o(cycles), .uart_tx_o(uart), .spi_cs_n_o(cs_n), .spi_sck_o(sck),
    .spi_mosi_o(mosi), .spi_miso_o(miso), .npu_irq_o(irq));
  integer frames=0, edges=0, irq_edges=0;
  time last_sck, last_cs;
  always @(posedge irq) if (rst_n) irq_edges++;
  always @(negedge cs_n) begin edges=0; last_cs=$time; end
  always @(posedge sck) if (rst_n) begin
    if (cs_n) $fatal(1,"SCK outside CS");
    if (edges==0 && $time-last_cs<240) $fatal(1,"CS setup shorter than six clocks");
    if (edges!=0 && $time-last_sck<240) $fatal(1,"SCK low too short");
    last_sck=$time; edges++;
  end
  always @(negedge sck) if (rst_n && !cs_n && edges!=0) begin
    if ($time-last_sck<240) $fatal(1,"SCK high too short");
    last_sck=$time;
  end
  always @(posedge cs_n) if (rst_n && edges!=0) begin
    if (edges!=80) $fatal(1,"Expected 80 SPI bits, got %0d",edges);
    if ($time-last_sck<240) $fatal(1,"CS hold too short");
    frames++;
  end
  always @(posedge clk) if (rst_n && status[31:16]==16'hdead)
    $fatal(1,"Firmware failure detail=%h PC=%h",detail,dut.i_addr);
  initial begin
    repeat (8) @(negedge clk); rst_n=1;
    wait(status==32'h600d600d);
    if (irq_edges!=16 || detail<190 || frames<1000)
      $fatal(1,"Insufficient exercise: checks=%0d IRQ=%0d frames=%0d",detail,irq_edges,frames);
    $display("PASS boot 1: CV32E40P firmware checks=%0d IRQ=%0d frames=%0d cycles=%0d",detail,irq_edges,frames,cycles);

    @(negedge clk); rst_n=0; frames=0; irq_edges=0;
    repeat(8) @(negedge clk); rst_n=1;
    wait(status==32'h600d600d);
    if (irq_edges!=16) $fatal(1,"Warm-reset IRQ mismatch");
    $display("PASS boot 2: warm reset, checks=%0d IRQ=%0d frames=%0d cycles=%0d",detail,irq_edges,frames,cycles);
    $finish;
  end
  initial begin
    repeat(20000000) @(posedge clk);
    $fatal(1,"SoC timeout status=%h detail=%h PC=%h",status,detail,dut.i_addr);
  end
endmodule
