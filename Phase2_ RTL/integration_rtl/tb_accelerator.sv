`timescale 1ns/1ps
module tb_accelerator;
  import activation_reference_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic PSEL = 0, PENABLE = 0, PWRITE = 0;
  logic [31:0] PADDR = 0, PWDATA = 0, PRDATA;
  logic PREADY, PSLVERR;
  logic req = 0, wen = 1;
  logic [31:0] addr = 0, wdata = 0, rdata;
  logic [3:0] be = 15;
  logic gnt, rvalid, error, irq;
  logic result_valid;
  logic signed [15:0] result_value;
  int checks = 0;

  accelerator_top dut (
    .clk(clk), .rst_n(rst_n), .PSEL(PSEL), .PENABLE(PENABLE), .PWRITE(PWRITE),
    .PADDR(PADDR), .PWDATA(PWDATA), .PRDATA(PRDATA), .PREADY(PREADY), .PSLVERR(PSLVERR),
    .tcdm_req_i(req), .tcdm_wen_i(wen), .tcdm_addr_i(addr), .tcdm_wdata_i(wdata),
    .tcdm_be_i(be), .tcdm_gnt_o(gnt), .tcdm_rvalid_o(rvalid), .tcdm_rdata_o(rdata),
    .tcdm_error_o(error), .irq_o(irq), .dbg_result_valid_o(result_valid), .dbg_result_o(result_value),
    .dbg_enable_o(), .dbg_activation_mode_o(), .dbg_error_threshold_o(), .dbg_iter_budget_o(),
    .dbg_core_start_o(), .dbg_sample_mode_o(), .dbg_core_valid_o(), .dbg_overflow_o(), .dbg_residual_o()
  );

  task automatic apb(input bit write, input int address, input int data, output int response,
      input bit expected_error = 0);
    @(negedge clk);
    PSEL = 1; PENABLE = 0; PWRITE = write; PADDR = address; PWDATA = data;
    @(negedge clk);
    PENABLE = 1;
    @(posedge clk);
    if (!PREADY || PSLVERR !== expected_error) $fatal(1,"APB failure at %h",address);
    response = PRDATA;
    @(negedge clk);
    PSEL = 0; PENABLE = 0;
  endtask

  task automatic bus(input bit write, input int address, input int data, output int response,
      input bit expected_error = 0, input bit [3:0] mask = 15);
    @(negedge clk);
    req = 1; wen = !write; addr = address; wdata = data; be = mask;
    @(posedge clk);
    if (!gnt) $fatal(1,"Missing TCDM grant");
    @(negedge clk);
    req = 0;
    if (!rvalid || error !== expected_error) $fatal(1,"TCDM failure addr=%h error=%b",address,error);
    response = rdata;
  endtask

  task automatic configure(input int mode, minimum = 14, maximum = 14, full = 14,
      threshold = 512, sampling = 1, qualification = 1);
    int response;
    apb(1,'h00,0,response);
    apb(1,'h14,threshold,response);
    apb(1,'h18,sampling,response);
    apb(1,'h20,minimum,response);
    apb(1,'h24,maximum,response);
    apb(1,'h28,full,response);
    apb(1,'h2c,qualification,response);
    apb(1,'h30,1,response);
    apb(1,'h34,0,response);
    apb(1,'h38,1,response);
    apb(1,'h00,(mode<<1)|1,response);
  endtask

  task automatic direct(input int x, mode, iterations, full, threshold,
      input bit sampled = 1);
    int response, expected, early_result, full_result;
    bus(1,'h200,x,response);
    for (int i = 0; i < 1500; i++) begin
      @(negedge clk);
      if (result_valid) break;
      if (i == 1499) $fatal(1,"Activation timeout");
    end
    early_result = activation_fixed(x,mode,iterations);
    full_result = activation_fixed(x,mode,full);
    expected = early_result;
    if (sampled && ((early_result > full_result ? early_result-full_result : full_result-early_result) > threshold))
      expected = full_result;
    if ($signed(result_value) != expected)
      $fatal(1,"EXACT check=%0d mode=%0d x=%0d iter=%0d actual_iter=%0d expected=%0d got=%0d",checks,mode,x,iterations,dut.u_activation.u_cordic_core.iter_budget_q,expected,$signed(result_value));
    repeat(3) @(negedge clk);
    checks++;
  endtask

  initial begin
    int response, sum, expected, before_count, x_fail;
    int weights[16], acts[4];
    int inputs[15] = '{-262144,-131072,-85197,-32768,-16384,-8192,-1,0,1,8192,16384,32768,85197,131072,262143};
    repeat(5) @(negedge clk);
    rst_n = 1;
    for (int mode = 0; mode < 4; mode++) begin
      for (int n = 6; n <= 16; n++) begin
        configure(mode,n,n,n);
        foreach(inputs[i]) direct(inputs[i],mode,n,n,512);
      end
      for (int pattern = 0; pattern < 4; pattern++) begin
        configure(mode);
        for (int i = 0; i < 16; i++) begin
          weights[i] = pattern == 3 ? ((i%2) ? -128 : 127) : (i%7)-3;
          bus(1,i*4,weights[i],response);
        end
        for (int i = 0; i < 4; i++) begin
          case(pattern)
            0: acts[i] = 0;
            1: acts[i] = i+1;
            2: acts[i] = i%2 ? -(i+1) : 0;
            3: acts[i] = i%2 ? -128 : 127;
          endcase
          bus(1,'h40+i*4,acts[i],response);
        end
        bus(1,'h104,pattern == 3 ? 4 : 0,response);
        bus(1,'h108,1,response);
        bus(1,'h100,1,response);
        bus(1,0,0,response,1);
        for (int timeout = 0; timeout < 8192; timeout++) begin
          bus(0,'h100,0,response);
          if (response[1]) break;
          if (timeout == 8191) $fatal(1,"NPU completion timeout");
        end
        for (int r = 0; r < 4; r++) begin
          sum = 0;
          for (int c = 0; c < 4; c++) sum += weights[r*4+c]*acts[c];
          bus(0,'h90+r*4,0,response);
          if (response != sum) $fatal(1,"MAC r=%0d expected=%0d got=%0d",r,sum,response);
          expected = activation_fixed(sat(sum >>> (pattern == 3 ? 4 : 0),19),mode,14);
          bus(0,'h80+r*4,0,response);
          if (response != expected) $fatal(1,"NPU activation expected=%0d got=%0d",expected,response);
          checks++;
        end
        if (!irq) $fatal(1,"Missing done IRQ");
        bus(1,'h100,2,response);
        if (irq) $fatal(1,"Done IRQ did not clear");
      end
    end
    configure(0,6,10,14,0);
    x_fail = 0;
    for(int x = 100; x < 16000; x+=73)
      if(activation_fixed(x,0,10) != activation_fixed(x,0,14)) begin x_fail=x; break; end
    if (!x_fail) $fatal(1,"No fallback stimulus");
    apb(0,'h10,0,before_count);
    direct(x_fail,0,10,14,0);
    apb(0,'h10,0,response);
    if (response != before_count+1) $fatal(1,"Fallback counter");
    direct(x_fail,0,14,14,0);
    configure(0,6,14,14,65535);
    direct(8192,0,14,14,65535);
    direct(8192,0,13,14,65535);
    apb(1,'h38,3,response);
    direct(8192,0,14,14,65535);
    direct(8192,0,14,14,65535);
    configure(0,14,14,14,512,2);
    apb(0,'h08,0,before_count);
    direct(8192,0,14,14,512,0);
    direct(8192,0,14,14,512,1);
    apb(0,'h08,0,response);
    if (response != before_count+1) $fatal(1,"Sampling count");
    configure(0,255,0,0);
    direct(8192,0,16,16,512);
    bus(0,'hfff,0,response,1);
    bus(1,0,'h55,response);
    bus(1,0,'haa,response,0,4'b1110);
    bus(0,0,0,response);
    if(response != 'h55) $fatal(1,"Byte enable");
    bus(1,'h100,1,response);
    @(negedge clk); rst_n = 0;
    repeat(4) @(negedge clk);
    rst_n = 1;
    bus(0,'h100,0,response);
    if(response != 0) $fatal(1,"Reset status");
    bus(0,0,0,response);
    if(response != 0) $fatal(1,"Reset buffers");
    bus(1,'h100,1,response,1);
    $display("PASS: %0d bit-exact activation/NPU output checks plus fallback, LUT, sampling, IRQ, byte-enable, busy rejection, and reset checks",checks);
    $finish;
  end
  initial begin
    #100000000;
    $fatal(1,"Global verification timeout");
  end
endmodule
