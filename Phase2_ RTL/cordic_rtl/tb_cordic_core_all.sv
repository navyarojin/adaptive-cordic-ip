`timescale 1ns/1ps

module tb_cordic_core_all;
  import cordic_pkg::*;

  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  ctrl_to_core_t ctrl_i;
  logic [ITER_CNT_WIDTH-1:0] full_iter_i;
  logic round_mode_en_i;
  core_to_ctrl_t ctrl_o;
  logic dbg_valid_o;
  logic signed [INTERNAL_WIDTH-1:0] dbg_full_result_o;
  logic dbg_overflow_o;

  cordic_core dut (
    .clk(clk), .rst_n(rst_n),
    .ctrl_i(ctrl_i), .full_iter_i(full_iter_i), .round_mode_en_i(round_mode_en_i),
    .ctrl_o(ctrl_o),
    .dbg_valid_o(dbg_valid_o), .dbg_full_result_o(dbg_full_result_o), .dbg_overflow_o(dbg_overflow_o)
  );

  int errors = 0;
  int total  = 0;
  int tanh_errors = 0, tanh_total = 0;
  int sig_errors  = 0, sig_total  = 0;

  
  
  
  task automatic run_case(input logic signed [INPUT_WIDTH-1:0] x_in,
                          input logic signed [OUTPUT_WIDTH-1:0] exp_early,
                          input logic signed [OUTPUT_WIDTH-1:0] exp_full,
                          input int unsigned exp_resid,
                          input logic exp_ov,
                          input logic rm,
                          input logic sigmoid_mode);
    total++;
    if (sigmoid_mode) sig_total++; else tanh_total++;

    @(posedge clk);
    ctrl_i.start        <= 1'b1;
    ctrl_i.x_in         <= x_in;
    ctrl_i.iter_budget  <= DEFAULT_MIN_ITER;
    ctrl_i.sample_mode  <= 1'b1;
    ctrl_i.sigmoid_mode <= sigmoid_mode;
    full_iter_i         <= FULL_ITER;
    round_mode_en_i     <= rm;
    @(posedge clk);
    ctrl_i.start <= 1'b0;

    wait (ctrl_o.valid == 1'b1);

    if (ctrl_o.early_result !== exp_early) begin
      $display("FAIL(early): mode=%s x_in=%0d rm=%0d got=%0d exp=%0d",
                sigmoid_mode ? "SIG" : "TANH", x_in, rm, ctrl_o.early_result, exp_early);
      errors++; if (sigmoid_mode) sig_errors++; else tanh_errors++;
    end
    if (ctrl_o.full_result !== exp_full) begin
      $display("FAIL(full):  mode=%s x_in=%0d rm=%0d got=%0d exp=%0d",
                sigmoid_mode ? "SIG" : "TANH", x_in, rm, ctrl_o.full_result, exp_full);
      errors++; if (sigmoid_mode) sig_errors++; else tanh_errors++;
    end
    if (ctrl_o.residual !== exp_resid) begin
      $display("FAIL(resid): mode=%s x_in=%0d rm=%0d got=%0d exp=%0d",
                sigmoid_mode ? "SIG" : "TANH", x_in, rm, ctrl_o.residual, exp_resid);
      errors++; if (sigmoid_mode) sig_errors++; else tanh_errors++;
    end
    if (ctrl_o.overflow !== exp_ov) begin
      $display("FAIL(ov):    mode=%s x_in=%0d rm=%0d got=%0d exp=%0d",
                sigmoid_mode ? "SIG" : "TANH", x_in, rm, ctrl_o.overflow, exp_ov);
      errors++; if (sigmoid_mode) sig_errors++; else tanh_errors++;
    end
    @(posedge clk);
  endtask

  initial begin
    
    
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_cordic_core_all);

    ctrl_i = '0;
    full_iter_i = FULL_ITER;
    round_mode_en_i = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    
    
    
    run_case(19'sh00000, 16'sh00c2, 16'shffff, 195, 1'b0, 1'b0, 1'b0);
    run_case(19'sh01333, 16'sh1422, 16'sh12a3, 383, 1'b0, 1'b0, 1'b0);
    run_case(19'sh7eccd, 16'shebdf, 16'shed5d, 382, 1'b0, 1'b0, 1'b0);
    run_case(19'sh03000, 16'sh2983, 16'sh28a8, 219, 1'b0, 1'b0, 1'b0);
    run_case(19'sh7c010, 16'shce9e, 16'shcf46, 168, 1'b0, 1'b0, 1'b0);
    run_case(19'sh04000, 16'sh3162, 16'sh30be, 164, 1'b0, 1'b0, 1'b0);
    run_case(19'sh7e000, 16'she1bf, 16'she269, 170, 1'b0, 1'b0, 1'b0);
    run_case(19'sh09333, 16'sh3ed3, 16'sh3eb9, 26,  1'b0, 1'b0, 1'b0);
    run_case(19'sh71333, 16'shc019, 16'shc014, 5,   1'b0, 1'b0, 1'b0);
    run_case(19'sh14c29, 16'sh3fff, 16'sh3fff, 0,   1'b0, 1'b0, 1'b0);
    run_case(19'sh6b3d7, 16'shc001, 16'shc001, 0,   1'b0, 1'b0, 1'b0);
    run_case(19'sh15333, 16'sh3fff, 16'sh3fff, 0,   1'b0, 1'b0, 1'b0);
    run_case(19'sh68000, 16'shc000, 16'shc000, 0,   1'b0, 1'b0, 1'b0);
    run_case(19'sh00002, 16'sh00c2, 16'sh0006, 188, 1'b0, 1'b0, 1'b0);
    run_case(19'sh7fffe, 16'shff3e, 16'sh0001, 195, 1'b0, 1'b0, 1'b0);

    
    
    
    run_case(19'sh00000, 16'sh00c1, 16'shffff, 194, 1'b0, 1'b1, 1'b0);
    run_case(19'sh01333, 16'sh1423, 16'sh12a4, 383, 1'b0, 1'b1, 1'b0);
    run_case(19'sh7eccd, 16'shebdd, 16'shed5c, 383, 1'b0, 1'b1, 1'b0);
    run_case(19'sh03000, 16'sh2983, 16'sh28a7, 220, 1'b0, 1'b1, 1'b0);
    run_case(19'sh7c010, 16'shce9e, 16'shcf49, 171, 1'b0, 1'b1, 1'b0);
    run_case(19'sh04000, 16'sh3162, 16'sh30bd, 165, 1'b0, 1'b1, 1'b0);
    run_case(19'sh7e000, 16'she1c0, 16'she26f, 175, 1'b0, 1'b1, 1'b0);
    run_case(19'sh09333, 16'sh3ed3, 16'sh3eba, 25,  1'b0, 1'b1, 1'b0);
    run_case(19'sh71333, 16'shc019, 16'shc014, 5,   1'b0, 1'b1, 1'b0);
    run_case(19'sh14c29, 16'sh3fff, 16'sh3fff, 0,   1'b0, 1'b1, 1'b0);
    run_case(19'sh6b3d7, 16'shc001, 16'shc001, 0,   1'b0, 1'b1, 1'b0);
    run_case(19'sh15333, 16'sh3fff, 16'sh3fff, 0,   1'b0, 1'b1, 1'b0);
    run_case(19'sh68000, 16'shc000, 16'shc000, 0,   1'b0, 1'b1, 1'b0);
    run_case(19'sh00002, 16'sh00c1, 16'sh0004, 189, 1'b0, 1'b1, 1'b0);
    run_case(19'sh7fffe, 16'shff3f, 16'sh0001, 194, 1'b0, 1'b1, 1'b0);

    
    
    
    run_case(19'sh00000, 16'sh2061, 16'sh1fff, 98,  1'b0, 1'b0, 1'b1);
    run_case(19'sh01333, 16'sh245b, 16'sh24c3, 104, 1'b0, 1'b0, 1'b1);
    run_case(19'sh7eccd, 16'sh1ba4, 16'sh1b3d, 103, 1'b0, 1'b0, 1'b1);
    run_case(19'sh03000, 16'sh2bd6, 16'sh2b78, 94,  1'b0, 1'b0, 1'b1);
    run_case(19'sh7c010, 16'sh10df, 16'sh1138, 89,  1'b0, 1'b0, 1'b1);
    run_case(19'sh04000, 16'sh2f20, 16'sh2ecb, 85,  1'b0, 1'b0, 1'b1);
    run_case(19'sh7e000, 16'sh17cc, 16'sh1828, 92,  1'b0, 1'b0, 1'b1);
    run_case(19'sh09333, 16'sh3a61, 16'sh3a2a, 55,  1'b0, 1'b0, 1'b1);
    run_case(19'sh71333, 16'sh01b5, 16'sh018b, 42,  1'b0, 1'b0, 1'b1);
    run_case(19'sh14c29, 16'sh3fa4, 16'sh3fa5, 1,   1'b0, 1'b0, 1'b1);
    run_case(19'sh6b3d7, 16'sh005b, 16'sh005a, 1,   1'b0, 1'b0, 1'b1);
    run_case(19'sh15333, 16'sh3fa4, 16'sh3fae, 10,  1'b0, 1'b0, 1'b1);
    run_case(19'sh68000, 16'sh0022, 16'sh0028, 6,   1'b0, 1'b0, 1'b1);
    run_case(19'sh20000, 16'sh3ffb, 16'sh3ffa, 1,   1'b0, 1'b0, 1'b1);
    run_case(19'sh60000, 16'sh0004, 16'sh0005, 1,   1'b0, 1'b0, 1'b1);

    
    
    
    run_case(19'sh00000, 16'sh2061, 16'sh2000, 97,  1'b0, 1'b1, 1'b1);
    run_case(19'sh01333, 16'sh245c, 16'sh24c6, 106, 1'b0, 1'b1, 1'b1);
    run_case(19'sh7eccd, 16'sh1ba5, 16'sh1b3b, 106, 1'b0, 1'b1, 1'b1);
    run_case(19'sh03000, 16'sh2bd6, 16'sh2b78, 94,  1'b0, 1'b1, 1'b1);
    run_case(19'sh7c010, 16'sh10e0, 16'sh113b, 91,  1'b0, 1'b1, 1'b1);
    run_case(19'sh04000, 16'sh2f20, 16'sh2ecb, 85,  1'b0, 1'b1, 1'b1);
    run_case(19'sh7e000, 16'sh17cd, 16'sh182a, 93,  1'b0, 1'b1, 1'b1);
    run_case(19'sh09333, 16'sh3a62, 16'sh3a2b, 55,  1'b0, 1'b1, 1'b1);
    run_case(19'sh71333, 16'sh01b6, 16'sh018c, 42,  1'b0, 1'b1, 1'b1);
    run_case(19'sh14c29, 16'sh3fa5, 16'sh3fa6, 1,   1'b0, 1'b1, 1'b1);
    run_case(19'sh6b3d7, 16'sh005c, 16'sh005b, 1,   1'b0, 1'b1, 1'b1);
    run_case(19'sh15333, 16'sh3fa5, 16'sh3faf, 10,  1'b0, 1'b1, 1'b1);
    run_case(19'sh68000, 16'sh0022, 16'sh0029, 7,   1'b0, 1'b1, 1'b1);
    run_case(19'sh20000, 16'sh3ffc, 16'sh3ffb, 1,   1'b0, 1'b1, 1'b1);
    run_case(19'sh60000, 16'sh0005, 16'sh0006, 1,   1'b0, 1'b1, 1'b1);

    $display("---------------------------------------------------");
    $display("TANH:    %0d / %0d passed", tanh_total - tanh_errors, tanh_total);
    $display("SIGMOID: %0d / %0d passed", sig_total - sig_errors, sig_total);
    $display("---------------------------------------------------");
    if (errors == 0)
      $display("ALL %0d CORDIC_CORE TESTS PASSED (tanh + sigmoid combined)", total);
    else
      $display("%0d / %0d CORDIC_CORE TESTS FAILED", errors, total);

    $finish;
  end

  initial begin
    #400000;
    $display("TIMEOUT -- a test case never asserted ctrl_o.valid");
    $finish;
  end

endmodule : tb_cordic_core_all
