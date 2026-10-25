`timescale 1ns/1ps
module tb_stream_dma;
  import activation_reference_pkg::*;
  import axi_vip_pkg::*;
  logic clk=0,rst_n=0,ps_reset=0;
  wire ps_clk_wire=clk,ps_reset_wire=ps_reset;
  wire [3:0] led;
  bit test_passed=0;
  logic cpu_en=0;
  logic [11:0] cpu_addr=0;
  logic [31:0] cpu_data=0;
  integer read_bursts=0,write_bursts=0;
  always #20 clk=~clk;
  initial begin #2000; ps_reset=1; end
  npu_system_wrapper dut (
    .DDR_addr(),.DDR_ba(),.DDR_cas_n(),.DDR_ck_n(),.DDR_ck_p(),.DDR_cke(),
    .DDR_cs_n(),.DDR_dm(),.DDR_dq(),.DDR_dqs_n(),.DDR_dqs_p(),.DDR_odt(),
    .DDR_ras_n(),.DDR_reset_n(),.DDR_we_n(),.FIXED_IO_ddr_vrn(),.FIXED_IO_ddr_vrp(),
    .FIXED_IO_mio(),.FIXED_IO_ps_clk(ps_clk_wire),.FIXED_IO_ps_porb(ps_reset_wire),
    .FIXED_IO_ps_srstb(ps_reset_wire),.reset_button(!rst_n),.led,.uart_tx());
  task automatic axi_write(input int address,value,input int bytes=4);
    xil_axi_resp_t response;
    dut.npu_system_i.ps7.inst.M_AXI_GP0.mst.AXI4_WRITE_BURST(0,address,0,
      bytes==1 ? XIL_AXI_SIZE_1BYTE : XIL_AXI_SIZE_4BYTE,
      XIL_AXI_BURST_TYPE_INCR,XIL_AXI_ALOCK_NOLOCK,0,0,0,0,0,32'(value),0,response);
    if (response!=0) $fatal(1,"AXI write response %0d",response);
  endtask
  task automatic axi_read(input int address,output int value);
    xil_axi_resp_t response;
    bit [63:0] data;
    dut.npu_system_i.ps7.inst.M_AXI_GP0.mst.AXI4LITE_READ_BURST(address,0,data,response);
    value=data[31:0];
    if (response!=0) $fatal(1,"AXI read response %0d",response);
  endtask
  task automatic cpu_write(input int address,value);
    @(negedge dut.npu_system_i.npu_host.inst.core.clk);
    cpu_en=1; cpu_addr=12'(address); cpu_data=32'(value);
    @(negedge dut.npu_system_i.npu_host.inst.core.clk); cpu_en=0;
  endtask
  task automatic dma_copy(input int source,destination,size);
    int status;
    for (int attempt=0;attempt<256;attempt++) begin
      axi_read('h40400004,status);
      if ((status&2) || (status&'h70)) break;
    end
    if (!(status&2) || (status&'h70)) $fatal(1,"DMA not ready %h",status);
    axi_write('h40400004,'h7000);
    axi_write('h40400018,source);
    axi_write('h40400020,destination);
    axi_write('h40400028,size);
    for (int attempt=0;attempt<2048;attempt++) begin
      axi_read('h40400004,status);
      if (status&'h70) $fatal(1,"DMA error %h",status);
      if (status&2) return;
    end
    $fatal(1,"DMA timeout");
  endtask
  always @(posedge dut.npu_system_i.npu_host.inst.core.clk) begin
    if (dut.npu_system_i.stream_dma_M_AXI_ARVALID && dut.npu_system_i.stream_dma_M_AXI_ARREADY) begin
      if (dut.npu_system_i.stream_dma_M_AXI_ARLEN>15) $fatal(1,"Unexpected read burst length");
      if (dut.npu_system_i.stream_dma_M_AXI_ARLEN>0) read_bursts++;
    end
    if (dut.npu_system_i.stream_dma_M_AXI_AWVALID && dut.npu_system_i.stream_dma_M_AXI_AWREADY) begin
      if (dut.npu_system_i.stream_dma_M_AXI_AWLEN>15) $fatal(1,"Unexpected write burst length");
      if (dut.npu_system_i.stream_dma_M_AXI_AWLEN>0) write_bursts++;
    end
  end
  initial begin
    int value,expected,input_value,lanes,words;
    logic [1023:0] memory_word;
    force dut.npu_system_i.npu_host.inst.core.stream_cpu_en=cpu_en;
    force dut.npu_system_i.npu_host.inst.core.stream_cpu_we=1;
    force dut.npu_system_i.npu_host.inst.core.stream_cpu_be=4'hf;
    force dut.npu_system_i.npu_host.inst.core.stream_cpu_addr=cpu_addr;
    force dut.npu_system_i.npu_host.inst.core.stream_cpu_wdata=cpu_data;
    repeat(64) @(negedge clk); rst_n=1;
    dut.npu_system_i.ps7.inst.fpga_soft_reset(1);
    #2000;
    dut.npu_system_i.ps7.inst.fpga_soft_reset(0);
    #10000;
    if (dut.npu_system_i.stream_dma.s_axi_lite_aresetn!==1'b1) $fatal(1,"CDMA reset remains asserted");
    axi_read('h40010000,value);
    if (value!='h53545231) $fatal(1,"AXI streaming identity");
    axi_read('h40010004,value);
    lanes=value&65535;
    if (lanes!=1 && lanes!=4 && lanes!=8 && lanes!=16) $fatal(1,"Invalid lane capability");
    words=64*lanes;
    axi_write('h40400000,4);
    do axi_read('h40400000,value); while (value&4);
    for (int i=0;i<words;i++) begin
      memory_word='0;
      memory_word[31:0]=32'((i-128)*256);
      dut.npu_system_i.ps7.inst.write_mem(memory_word,'h00100000+4*i,4);
    end
    dma_copy('h00100000,'h40011000,4*words);
    axi_write('h40011000,'haa,1);
    cpu_write('h20,1);
    cpu_write('h24,'h000e0e0e);
    cpu_write('h28,'h00010000);
    cpu_write('h10,'ha5004000);
    cpu_write('h14,1);
    axi_write('h40011004,0);
    do axi_read('h40010008,value); while (!(value&'h10000));
    axi_read('h4001000c,value);
    if (!(value&2)) $fatal(1,"AXI buffer ownership not enforced");
    dma_copy('h40013000,'h00110000,4*words);
    for (int i=0;i<words;i++) begin
      dut.npu_system_i.ps7.inst.read_mem('h00110000+4*i,4,memory_word);
      input_value=i==0 ? -32598 : (i-128)*256;
      expected=activation_fixed(input_value,0,14);
      if ($signed(memory_word[31:0])!=expected) $fatal(1,"DMA result index=%0d got=%0d expected=%0d",i,$signed(memory_word[31:0]),expected);
    end
    if (read_bursts==0 || write_bursts==0) $fatal(1,"No multi-beat bursts observed");
    cpu_write('h18,'h100);
    axi_read('h40010008,value);
    if (value&'h30300) $fatal(1,"DMA job release failed");
    rst_n=0;
    repeat(64) @(negedge clk); rst_n=1;
    #10000;
    axi_read('h40010000,value);
    if (value!='h53545231) $fatal(1,"AXI reset recovery");
    test_passed=1;
    $display("PASS vendor AXI CDMA: lanes=%0d results=%0d DDR/BRAM burst transfers, byte enables, ownership, completion and reset; read bursts=%0d write bursts=%0d",lanes,words,read_bursts,write_bursts);
    $finish;
  end
  initial begin #2000000; $fatal(1,"Vendor DMA simulation timeout"); end
endmodule
