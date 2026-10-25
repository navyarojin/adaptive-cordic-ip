`timescale 1ns/1ps
module tb_activation_accuracy #(parameter int ACTIVATION_LANES = 1);
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
  int cycle_count = 0, started_cycle = 0, activation_cycle = 0;
  bit measuring = 0;
  always @(negedge clk) begin
    cycle_count++;
    if (!rst_n) measuring = 0;
    else begin
      if (dut.u_npu.clear_i) begin
        measuring = 1;
        started_cycle = cycle_count;
        activation_cycle = 0;
      end
      if (measuring && dut.act_start && activation_cycle == 0)
        activation_cycle = cycle_count;
      if (measuring && dut.done_q) begin
        $display("BENCH,%0d,%0d,%0d,%0d",ACTIVATION_LANES,dut.dbg_activation_mode_o,
          cycle_count-started_cycle,cycle_count-activation_cycle);
        measuring = 0;
      end
    end
  end

  accelerator_top #(.ACTIVATION_LANES(ACTIVATION_LANES)) dut (
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
    int response, before_samples;
    real x, ideal, measured, err, abs_sum, sq_sum, maximum;
    int samples;
    repeat(5) @(negedge clk);
    rst_n=1;
    for (int mode=0; mode<2; mode++) begin
      for (int iterations=14; iterations<=16; iterations+=2) begin
        for (int extent=1; extent<=4; extent+=3) begin
          configure(mode,iterations,iterations,iterations);
          abs_sum=0.0; sq_sum=0.0; maximum=0.0; samples=0;
          for (int input_value=-extent*16384; input_value<=extent*16384; input_value+=64) begin
            direct(input_value,mode,iterations,iterations,512);
            x=real'(input_value)/16384.0;
            ideal=mode==0 ? ($exp(2.0*x)-1.0)/($exp(2.0*x)+1.0) : 1.0/(1.0+$exp(-x));
            measured=real'($signed(result_value))/16384.0;
            err=measured-ideal;
            if(err<0) err=-err;
            abs_sum+=err; sq_sum+=err*err;
            if(err>maximum) maximum=err;
            samples++;
          end
          $display("ACCURACY,%0d,%0d,%0d,%0d,%.10f,%.10f,%.10f",mode,iterations,extent,samples,abs_sum/samples,$sqrt(sq_sum/samples),maximum);
        end
      end
    end
    configure(0,6,10,14,0,1);
    apb(0,'h08,0,before_samples);
    for (int i=0;i<16;i++) bus(1,i*4,i%4==0 ? (i==0 ? 0 : i==4 ? 100 : i==8 ? -100 : 127) : 0,response);
    for (int i=0;i<4;i++) bus(1,'h40+i*4,i==0 ? 100 : 0,response);
    bus(1,'h100,1,response);
    for (int i=0;i<4096;i++) begin
      bus(0,'h100,0,response);
      if(response[1]) break;
      if(i==4095) $fatal(1,"Mixed latency timeout");
    end
    for (int i=0;i<4;i++) begin
      bus(0,'h80+i*4,0,response);
      if(response!=activation_fixed(i==0 ? 0 : i==1 ? 10000 : i==2 ? -10000 : 12700,0,14))
        $fatal(1,"Mixed latency collector lane %0d",i);
    end
    apb(0,'h08,0,response);
    if(response-before_samples!=4) $fatal(1,"Aggregate sample delta %0d",response-before_samples);
    if(ACTIVATION_LANES==4) begin
      configure(0,6,10,14,0,2);
      direct(10000,0,10,14,0,0);
      bus(1,0,100,response);
      apb(0,'h08,0,before_samples);
      bus(1,'h100,1,response);
      for(int i=0;i<4096;i++) begin
        bus(0,'h100,0,response);
        if(response[1]) break;
        if(i==4095) $fatal(1,"Unequal sampling timeout");
      end
      for(int i=0;i<4;i++) begin
        bus(0,'h80+i*4,0,response);
        if(response!=activation_fixed(i<2 ? 10000 : i==2 ? -10000 : 12700,0,i==0 ? 14 : 10))
          $fatal(1,"Unequal sampling output lane %0d",i);
      end
      apb(0,'h08,0,response);
      if(response-before_samples!=1) $fatal(1,"Per-lane sampling phase count");
    end
    @(negedge clk);
    PSEL=1; PENABLE=0; PWRITE=1; PADDR=0; PWDATA=0;
    @(negedge clk);
    PENABLE=1; req=1; wen=0; addr='h100; wdata=1; be=15;
    @(negedge clk);
    if(!error) $fatal(1,"Concurrent disable/start was accepted");
    PSEL=0; PENABLE=0; req=0;
    bus(0,'h100,0,response);
    if(response[0]) $fatal(1,"Concurrent config/start left engine busy");
    $display("PASS accuracy sweep, mixed-latency collection, aggregate counters and concurrent configuration rejection; lanes=%0d",ACTIVATION_LANES);
    $finish;
  end
  initial begin #100000000; $fatal(1,"Accuracy timeout"); end
endmodule
