`timescale 1ns/1ps
module tb_spi_bridge;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  spi_host_if host();
  logic psel, penable, pwrite, pready = 0, perror = 0;
  logic [31:0] paddr, pwdata, prdata = 32'h1234_abcd;
  logic req, wen, gnt = 0, rvalid = 0, error = 0;
  logic [31:0] addr, wdata, rdata = 32'hdead_beef;
  logic [3:0] be;
  int apb_count = 0, tcdm_count = 0, checks = 0;
  npu_spi_bridge dut (.clk, .rst_n, .spi_cs_n_i(host.cs_n), .spi_sck_i(host.sck),
    .spi_mosi_i(host.mosi), .spi_miso_o(host.miso), .spi_miso_oe_o(host.miso_oe),
    .PSEL(psel), .PENABLE(penable), .PWRITE(pwrite), .PADDR(paddr), .PWDATA(pwdata),
    .PRDATA(prdata), .PREADY(pready), .PSLVERR(perror), .tcdm_req_o(req), .tcdm_wen_o(wen),
    .tcdm_addr_o(addr), .tcdm_wdata_o(wdata), .tcdm_be_o(be), .tcdm_gnt_i(gnt),
    .tcdm_rvalid_i(rvalid), .tcdm_error_i(error), .tcdm_rdata_i(rdata));
  always @(posedge clk) begin
    if (rst_n && psel && penable && pready) apb_count++;
    if (rst_n && req && gnt) tcdm_count++;
  end

  initial begin
    logic [79:0] response;
    logic [31:0] result;
    #113; rst_n = 1; #100;
    host.transfer({8'h02,8'h0f,32'h20,32'h8765_4321},response);
    repeat (12) begin
      @(negedge clk);
      if (!psel || !penable || !pwrite || paddr != 'h20 || pwdata != 'h8765_4321)
        $fatal(1,"APB request not stable under wait state");
    end
    host.transfer(0,response);
    if (response[79:72] != 1) $fatal(1,"Busy status missing");

    host.transfer({8'h04,8'h0f,32'h40,32'h55},response);
    if (req || paddr != 'h20 || pwdata != 'h8765_4321) $fatal(1,"Busy command replaced request");
    @(negedge clk); pready = 1;
    repeat (3) @(negedge clk);
    pready = 0;
    host.transfer(0,response);
    if (response[79:72] != 2 || response[71:40] != 0 || apb_count != 1 || tcdm_count != 0)
      $fatal(1,"APB completion/replay failure");
    checks += 4;

    host.transfer({8'h01,8'h0f,32'h24,32'b0},response);
    fork
      host.transfer(0,response);
      begin #500; @(negedge clk); pready = 1; repeat (3) @(negedge clk); pready = 0; end
    join
    if (response[79:72] != 1 || response[71:40] != 0) $fatal(1,"Response changed mid-frame");
    host.transfer(0,response);
    if (response[79:72] != 2 || response[71:40] != prdata) $fatal(1,"APB read response");
    checks += 2;

    host.transfer({8'h03,8'h05,32'h80,32'b0},response);
    repeat (12) begin
      @(negedge clk);
      if (!req || !wen || addr != 'h80 || be != 5) $fatal(1,"TCDM grant stall");
    end
    @(negedge clk); gnt = 1;
    @(negedge clk); gnt = 0;
    if (req) $fatal(1,"TCDM request repeated after grant");
    host.transfer(0,response);
    if (response[79:72] != 1) $fatal(1,"TCDM response wait lost");
    @(negedge clk); rvalid = 1;
    @(negedge clk); rvalid = 0;
    host.transfer(0,response);
    if (response[79:72] != 2 || response[71:40] != rdata || tcdm_count != 1)
      $fatal(1,"Delayed TCDM response");
    checks += 3;

    @(negedge clk); gnt = 1; rvalid = 1; error = 1;
    host.access(4,0,'ha5,result,1,8'h01);
    if (result != 4 || tcdm_count != 2) $fatal(1,"Immediate TCDM error");
    @(negedge clk); gnt = 0; rvalid = 0; error = 0; pready = 1; perror = 1;
    host.access(1,0,0,result,1);
    if (result != 4) $fatal(1,"APB slave error");
    @(negedge clk); pready = 0; perror = 0;
    checks += 2;

    host.transfer({8'h04,8'h0f,32'b0,32'h55},response);
    if (!req) $fatal(1,"No request before reset");
    @(negedge clk); rst_n = 0;
    #23;
    if (req || psel || host.miso_oe) $fatal(1,"Reset failed to cancel request");
    rst_n = 1; #100;
    host.transfer(0,response);
    if (response != 0) $fatal(1,"Reset status not cleared");
    checks++;
    $display("PASS tb_spi_bridge: %0d protocol checks; stalls, busy rejection, response snapshots, slave errors and reset",checks);
    $finish;
  end
  initial begin #10000000; $fatal(1,"Bridge test timeout"); end
endmodule

`timescale 1ns/1ps
module tb_npu_spi #(parameter int ACTIVATION_LANES = 1);
  import activation_reference_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  spi_host_if host();
  wire irq;
  npu_spi_top #(.ACTIVATION_LANES(ACTIVATION_LANES)) dut (.clk, .rst_n, .spi_cs_n_i(host.cs_n), .spi_sck_i(host.sck),
    .spi_mosi_i(host.mosi), .spi_miso_o(host.miso), .spi_miso_oe_o(host.miso_oe), .irq_o(irq));
  int checks = 0;

  task automatic configure(input int mode, input int minimum = 14,
      maximum = 14, full = 14, threshold = 512);
    logic [31:0] r;
    host.access(2,'h00,0,r);
    host.access(2,'h14,threshold,r);
    host.access(2,'h18,1,r);
    host.access(2,'h20,minimum,r);
    host.access(2,'h24,maximum,r);
    host.access(2,'h28,full,r);
    host.access(2,'h2c,1,r);
    host.access(2,'h30,1,r);
    host.access(2,'h34,0,r);
    host.access(2,'h38,1,r);
    host.access(2,'h00,(mode<<1)|1,r);
    host.access(1,'h00,0,r);
    if (r !== ((mode<<1)|1)) $fatal(1,"APB control readback");
    checks++;
  endtask

  initial begin
    logic [31:0] r;
    logic [79:0] response;
    int weights[16], acts[4];
    int sum, expected, shift, fallback_x;
    #113; rst_n = 1; #200;
    host.transfer(0,response);
    if (response != 0) $fatal(1,"Reset response");
    for (int mode = 0; mode < 4; mode++) begin
      for (int pattern = 0; pattern < 4; pattern++) begin
        configure(mode);

        host.low_time = time'(61 + pattern * 11);
        host.high_time = time'(69 + pattern * 7);
        for (int i = 0; i < 16; i++) begin
          weights[i] = pattern == 3 ? ((i%2 != 0) ? -128 : 127) : (i%7)-3;
          host.access(4,i*4,weights[i],r);
        end
        for (int i = 0; i < 4; i++) begin
          case (pattern)
            0: acts[i] = 0;
            1: acts[i] = i+1;
            2: acts[i] = i%2 != 0 ? -(i+1) : 0;
            3: acts[i] = i%2 != 0 ? -128 : 127;
          endcase
          host.access(4,'h40+i*4,acts[i],r);
        end
        shift = pattern == 3 ? 4 : 0;
        host.access(4,'h104,shift,r);
        host.access(4,'h108,1,r);
        host.access(4,'h100,1,r);
        for (int k = 0; k < 20; k++) begin
          host.access(3,'h100,0,r);
          if (r[1]) break;
          if (k == 19) $fatal(1,"NPU completion timeout");
        end
        if (!irq) $fatal(1,"NPU interrupt missing");
        for (int row = 0; row < 4; row++) begin
          sum = 0;
          for (int col = 0; col < 4; col++) sum += weights[row*4+col]*acts[col];
          host.access(3,'h90+row*4,0,r);
          if ($signed(r) !== sum) $fatal(1,"MAC mode=%0d pattern=%0d row=%0d got=%0d expected=%0d",mode,pattern,row,$signed(r),sum);
          expected = activation_fixed(sat(longint'(sum) >>> shift,19),mode,14);
          host.access(3,'h80+row*4,0,r);
          if ($signed(r) !== expected) $fatal(1,"Activation mode=%0d row=%0d got=%0d expected=%0d",mode,row,$signed(r),expected);
          checks += 2;
        end
        host.access(4,'h100,2,r);
        if (irq) $fatal(1,"NPU interrupt not cleared");
      end
    end

    host.access(4,0,'h55,r);
    host.access(4,0,'haa,r,0,8'h0e);
    host.access(3,0,0,r);
    if (r != 'h55) $fatal(1,"Byte enable not preserved");
    host.access(1,'hfc,0,r,1);
    if (r != 4) $fatal(1,"APB error not propagated");
    host.access(3,'hffc,0,r,1);
    if (r != 4) $fatal(1,"TCDM error not propagated");
    host.access(4,1,0,r,1);
    if (r != 2) $fatal(1,"Alignment error missing");
    host.access(8'hff,0,0,r,1);
    if (r != 1) $fatal(1,"Opcode error missing");
    host.access(2,0,0,r,1,8'h01);
    if (r != 3) $fatal(1,"Partial APB write not rejected");
    host.access(4,0,0,r,1,8'hff);
    if (r != 3) $fatal(1,"Reserved mask not rejected");
    host.access(3,0,0,r);
    if (r != 'h55) $fatal(1,"Rejected command changed data");

    configure(0,6,10,14,0);
    fallback_x = 0;
    for (int x = 100; x < 16000; x += 73)
      if (activation_fixed(x,0,10) != activation_fixed(x,0,14)) begin
        fallback_x = x; break;
      end
    if (fallback_x == 0) $fatal(1,"No fallback stimulus");
    host.access(4,'h200,fallback_x,r);
    host.access(3,'h204,0,r);
    if ($signed(r) != activation_fixed(fallback_x,0,14)) $fatal(1,"Fallback result");
    host.access(1,'h10,0,r);
    if (r != 1) $fatal(1,"Fallback count");
    checks += 11;

    host.transfer({8'h04,8'h0f,32'b0,32'ha5},response,79);
    host.access(3,0,0,r);
    if (r != 'h55) $fatal(1,"Short frame committed");
    host.transfer({8'h04,8'h0f,32'b0,32'ha5},response,200);
    host.access(3,0,0,r);
    if (r != 'h55) $fatal(1,"Long frame committed");

    host.check_oe = 0;
    fork
      host.transfer({8'h04,8'h0f,32'b0,32'ha5},response);
      begin #1000; rst_n = 0; #100; rst_n = 1; end
    join
    host.check_oe = 1;
    #200;
    host.access(3,0,0,r);
    if (r != 0) $fatal(1,"Reset frame committed");
    host.access(4,'h100,1,r,1);
    checks += 4;
    $display("PASS tb_npu_spi: %0d checks; 16 NPU mode/pattern combinations, SPI errors, byte enables, fallback, framing and reset",checks);
    $finish;
  end
  initial begin #100000000; $fatal(1,"Global SPI test timeout"); end
endmodule
