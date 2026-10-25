`timescale 1ns/1ps
module tb_fused_layer;
  import activation_reference_pkg::*;
  logic clk=0,rst_n=0,cpu_en_i=0,cpu_we_i=0,ps_en_i=0;
  logic [3:0] cpu_be_i=15,ps_we_i=0;
  logic [11:0] cpu_addr_i=0;
  logic [15:0] ps_addr_i=0;
  logic [31:0] cpu_wdata_i=0,ps_wdata_i=0;
  wire [31:0] cpu_rdata_o,ps_rdata_o;
  wire irq_o;
  int expected[0:1][0:63][0:3];
  int checks=0,cycle=0,submit_cycle[0:1],input_cycle[0:1],output_cycle[0:1];
  int in_count[0:1],out_count[0:1],stalls[0:1],ref_stalls[0:1];
  int measured[0:1][0:6];
  always #5 clk=~clk;
  stream_mmio #(.LANES(4)) dut(.*);
  function automatic int sample(input int b,i,c);
    return ((i*13+c*37+b*19)%256)-128;
  endfunction
  function automatic int weight(input int b,r,c);
    return ((r*11-c*7+b*3)%31)-15;
  endfunction
  function automatic int bias_value(input int b,r);
    case(r)
      0:return b==0 ? 32'sh7fffffff : 32'sh80000000;
      1:return b==0 ? 32'sh80000000 : 32'sh7fffffff;
      default:return (b*2-1)*(r*613+1);
    endcase
  endfunction
  always @(posedge clk) begin
    int b;
    cycle++;
    if (rst_n) begin
      if (dut.engine.submit && dut.engine.legal_command) begin
        b=dut.descriptor[0]; submit_cycle[b]=cycle;
        in_count[b]=0; out_count[b]=0; stalls[b]=0; ref_stalls[b]=0;
      end
      b=dut.engine.active.bank;
      if (dut.engine.accept_input) begin
        if (in_count[b]==0) input_cycle[b]=cycle;
        in_count[b]++;
      end
      if (dut.engine.busy && dut.engine.read_valid && !dut.engine.front_ready) stalls[b]++;
      if (dut.engine.busy && dut.engine.activation_valid && dut.engine.reference_stall) ref_stalls[b]++;
      if (dut.engine.array_valid) begin
        if (out_count[b]==0) output_cycle[b]=cycle;
        out_count[b]++;
        measured[b][0]=input_cycle[b]-submit_cycle[b];
        measured[b][1]=output_cycle[b]-input_cycle[b];
        measured[b][2]=cycle-input_cycle[b];
        measured[b][3]=in_count[b]; measured[b][4]=out_count[b];
        measured[b][5]=stalls[b]; measured[b][6]=ref_stalls[b];
      end
    end
  end
  task automatic cpu_write(input int address,value);
    @(negedge clk); cpu_en_i=1; cpu_we_i=1; cpu_addr_i=12'(address); cpu_wdata_i=value;
    @(negedge clk); cpu_en_i=0; cpu_we_i=0;
  endtask
  task automatic ps_read(input int address,output int value);
    @(negedge clk); ps_en_i=1; ps_we_i=0; ps_addr_i=16'(address);
    @(negedge clk); value=ps_rdata_o; ps_en_i=0;
  endtask
  task automatic fill_banks;
    for (int b=0;b<2;b++) for (int i=0;i<64;i++) for (int c=0;c<4;c++) begin
      @(negedge clk); ps_en_i=1; ps_we_i=15;
      ps_addr_i=16'('h1000+b*'h1000+16*i+4*c); ps_wdata_i=sample(b,i,c);
    end
    @(negedge clk); ps_en_i=0; ps_we_i=0;
  endtask
  task automatic configure(input int b,mode,count,input bit fused,input bit sampled=0);
    int word;
    longint signed sum;
    cpu_write('h20,(mode<<1)|1);
    cpu_write('h24,sampled ? 'h0e0e06 : 'h0e0e0e);
    cpu_write('h28,sampled ? 'h10000 : 0);
    cpu_write('h38,(b<<8)|int'(fused));
    for (int r=0;r<4;r++) begin
      word=0;
      for (int c=0;c<4;c++) word|=(weight(b,r,c)&255)<<(8*c);
      cpu_write('h40+4*r,word); cpu_write('h50+4*r,bias_value(b,r));
    end
    for (int i=0;i<count;i++) for (int r=0;r<4;r++) begin
      sum=bias_value(b,r);
      for (int c=0;c<4;c++) sum+=sample(b,i,c)*weight(b,r,c);
      expected[b][i][r]=activation_fixed(fused ? sat(rounded_div(sum,64'sd1<<b),19) : sample(b,i,r),mode,14);
    end
    cpu_write('h10,((mode*2+b+1)<<16)|(count<<8)|b);
    cpu_write('h14,1);
  endtask
  initial begin
    int value,count;
    repeat(3) @(negedge clk); rst_n=1;
    ps_read('h34,value); if(value!='h10007) $fatal(1,"Fused capability missing");
    fill_banks();
    for (int mode=0;mode<6;mode++) begin
      count=mode==4 ? 1 : 64;
      configure(0,mode%4,count,mode!=4,mode==5);
      configure(1,mode%4,count,mode!=4,mode==5);

      cpu_write('h38,0);
      for(int r=0;r<4;r++) begin cpu_write('h40+r*4,0); cpu_write('h50+r*4,0); end
      wait(dut.done==3);
      ps_read('hc,value); if(value!=0) $fatal(1,"Unexpected MMIO error %h",value);
      for (int b=0;b<2;b++) begin
        for (int i=0;i<count;i++) for (int r=0;r<4;r++) begin
          ps_read('h3000+b*'h1000+i*16+r*4,value);
          if(value!=expected[b][i][r]) $fatal(1,"Fused mode %0d bank %0d row %0d lane %0d got %0d expected %0d",mode,b,i,r,value,expected[b][i][r]);
          checks++;
        end
        for (int c=0;c<7;c++) begin
          ps_read('h80+b*'h20+c*4,value);
          if(value!=measured[b][c]) $fatal(1,"Counter bank %0d index %0d got %0d expected %0d",b,c,value,measured[b][c]);
        end
        if(measured[b][3]!=count || measured[b][4]!=count) $fatal(1,"Vector count mismatch");
        if(mode==5 && measured[b][6]==0) $fatal(1,"Shared-reference stall test did not exercise stalls");
        cpu_write('h18,'h100|b);
      end
      if(irq_o) $fatal(1,"Release did not clear IRQ");
    end
    configure(0,0,64,1);
    repeat(8) @(negedge clk); rst_n=0;
    repeat(3) @(negedge clk); rst_n=1;
    repeat(200) @(negedge clk);
    ps_read(8,value); if((value&'h30300)!=0) $fatal(1,"Reset left stale ownership");
    ps_read('h80,value); if(value!=0) $fatal(1,"Reset left stale counters");
    $display("PASS fused layer: %0d outputs; four activation modes; two banks; config snapshots; exact counters; activation-only compatibility; reset",checks);
    $finish;
  end
  initial begin #2000000; $fatal(1,"Fused layer timeout"); end
endmodule
