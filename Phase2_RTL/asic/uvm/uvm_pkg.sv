`timescale 1ns/1ps
package stream_uvm_pkg;
  import uvm_pkg::*;
  import activation_reference_pkg::*;
  `include "uvm_macros.svh"
  typedef enum {CPU_WRITE, CPU_READ, HOST_WRITE, HOST_READ, RESET_BUS, IDLE_BUS} bus_op;

  class stream_item extends uvm_sequence_item;
    `uvm_object_utils(stream_item)
    bus_op op;
    bit [15:0] address;
    bit [31:0] data;
    logic [31:0] response;
    bit [3:0] enables=15;
    int cycles=1;
    function new(string name="stream_item"); super.new(name); endfunction
  endclass

  class stream_driver extends uvm_driver #(stream_item);
    `uvm_component_utils(stream_driver)
    virtual stream_if vif;
    function new(string name,uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if(!uvm_config_db#(virtual stream_if)::get(this,"","vif",vif))
        `uvm_fatal("VIF","Missing stream interface")
    endfunction
    task run_phase(uvm_phase phase);
      forever begin
        seq_item_port.get_next_item(req);
        @(negedge vif.clk);
        case(req.op)
          RESET_BUS: begin
            vif.rst_n=0; vif.cpu_en_i=0; vif.ps_en_i=0;
            repeat(4) @(negedge vif.clk);
            vif.rst_n=1;
          end
          IDLE_BUS: repeat(req.cycles) @(negedge vif.clk);
          CPU_WRITE,CPU_READ: begin
            vif.cpu_en_i=1; vif.cpu_we_i=req.op==CPU_WRITE;
            vif.cpu_addr_i=req.address[11:0]; vif.cpu_be_i=req.enables; vif.cpu_wdata_i=req.data;
            @(negedge vif.clk); req.response=vif.cpu_rdata_o; vif.cpu_en_i=0;
          end
          HOST_WRITE,HOST_READ: begin
            vif.ps_en_i=1; vif.ps_we_i=req.op==HOST_WRITE ? req.enables : 0;
            vif.ps_addr_i=req.address; vif.ps_wdata_i=req.data;
            @(negedge vif.clk); req.response=vif.ps_rdata_o; vif.ps_en_i=0;
          end
        endcase
        seq_item_port.item_done();
      end
    endtask
  endclass

  class stream_monitor extends uvm_component;
    `uvm_component_utils(stream_monitor)
    virtual stream_if vif;
    uvm_analysis_port #(stream_item) observed;
    function new(string name,uvm_component parent);
      super.new(name,parent); observed=new("observed",this);
    endfunction
    real sample_delay_ns=1.0;
    function void build_phase(uvm_phase phase);
      if(!uvm_config_db#(virtual stream_if)::get(this,"","vif",vif)) `uvm_fatal("VIF","Missing interface")
      if ($value$plusargs("SAMPLE_NS=%f",sample_delay_ns)) begin
        if (sample_delay_ns<=0) `uvm_fatal("SAMPLE","SAMPLE_NS must be positive")
      end
    endfunction
    task run_phase(uvm_phase phase);
      stream_item t;
      forever begin
        @(posedge vif.clk);
        t=stream_item::type_id::create("observed_item");
        if(!vif.rst_n) t.op=RESET_BUS;
        else if(vif.cpu_en_i) begin
          t.op=vif.cpu_we_i ? CPU_WRITE : CPU_READ;
          t.address={4'b0,vif.cpu_addr_i}; t.data=vif.cpu_wdata_i; t.enables=vif.cpu_be_i;
        end else if(vif.ps_en_i) begin
          t.op=(|vif.ps_we_i) ? HOST_WRITE : HOST_READ;
          t.address=vif.ps_addr_i; t.data=vif.ps_wdata_i; t.enables=vif.ps_we_i;
        end else continue;
        #(sample_delay_ns);
        t.response=(t.op==CPU_READ) ? vif.cpu_rdata_o : vif.ps_rdata_o;
        observed.write(t);
      end
    endtask
  endclass

  class stream_scoreboard extends uvm_component;
    `uvm_component_utils(stream_scoreboard)
    uvm_analysis_imp #(stream_item,stream_scoreboard) observed;
    bit [31:0] model[16],weights[4],biases[4],descriptor;
    bit [31:0] inputs[2][64][4];
    int expected[2][64][4],counts[2];
    bit pending[2],finished[2],loaded,enabled=1;
    int mode=3,kind,shift,checked,jobs,rejected,reset_busy,reference_iterations=14;
    int cov_bank,cov_count,cov_kind,cov_mode;
    covergroup jobs_cg;
      option.per_instance=1;
      bank: coverpoint cov_bank { bins banks[]={0,1}; }
      count: coverpoint cov_count { bins one={1}; bins two={2}; bins partial={15}; bins full={64}; bins other={[3:14],[16:63]}; }
      kind_cp: coverpoint cov_kind { bins activation={0}; bins fused={1}; bins model={3}; }
      mode_cp: coverpoint cov_mode { bins modes[]={[0:3]}; }
      bank_kind: cross bank,kind_cp;
    endgroup
    function new(string name,uvm_component parent);
      super.new(name,parent); observed=new("observed",this); jobs_cg=new;
    endfunction
    function int requant(int value);
      int q;
      q=int'(rounded_div(value,128));
      return q>127 ? 127 : (q< -128 ? -128 : q);
    endfunction
    function void predict(int bank,int count);
      int hidden[4],value;
      longint signed sum;
      for(int v=0;v<count;v++) begin
        for(int r=0;r<4;r++) begin
          if(kind==0) value=$signed(inputs[bank][v][r][18:0]);
          else begin
            sum=$signed(kind==3 ? model[4+r] : biases[r]);
            for(int c=0;c<4;c++) begin
              if(kind==3) sum+=longint'($signed(model[r][8*c+:8]))*$signed(inputs[bank][v][c][7:0]);
              else sum+=longint'($signed(weights[r][8*c+:8]))*$signed(inputs[bank][v][c][7:0]);
            end
            value=sat(rounded_div(sum,64'sd1<<shift),19);
          end
          hidden[r]=activation_fixed(value,kind==3 ? 0 : mode,kind==3 ? 14 : reference_iterations);
          expected[bank][v][r]=hidden[r];
        end
        if(kind==3) for(int r=0;r<4;r++) begin
          sum=$signed(model[12+r]);
          for(int c=0;c<4;c++) sum+=longint'($signed(model[8+r][8*c+:8]))*requant(hidden[c]);
          expected[bank][v][r]=activation_fixed(sat(sum,19),1,14);
        end
      end
      pending[bank]=1; finished[bank]=0; counts[bank]=count; jobs++;
      cov_bank=bank; cov_count=count; cov_kind=kind; cov_mode=mode; jobs_cg.sample();
    endfunction
    function void write(stream_item t);
      int a,b,v,l,n;
      a=int'(t.address);
      if(t.op==RESET_BUS) begin
        if(pending[0] || pending[1]) reset_busy++;
        pending[0]=0; pending[1]=0; finished[0]=0; finished[1]=0;
        loaded=0; enabled=1; reference_iterations=14; descriptor=0; mode=3; kind=0; shift=0;
        foreach(model[i]) model[i]=0;
        foreach(weights[i]) begin weights[i]=0; biases[i]=0; end
      end else if(t.op==CPU_WRITE && t.enables==15 && a%4==0) begin
        case(a)
          'h010: descriptor=t.data;
          'h020: begin mode=int'(t.data[2:1]); enabled=t.data[0]; end
          'h024: begin
            int minimum;
            minimum=int'(t.data[7:0]);
            if(minimum<6) minimum=6;
            if(minimum>16) minimum=16;
            reference_iterations=int'(t.data[23:16]);
            if(reference_iterations<minimum) reference_iterations=minimum;
            if(reference_iterations>16) reference_iterations=16;
          end
          'h038: begin kind=int'(t.data[1:0]); shift=int'(t.data[12:8]); end
          'h03c: loaded=t.data[0];
          'h014: if(t.data[0]) begin
            b=int'(descriptor[0]); n=int'(descriptor[14:8]);
            if(pending[b] || !enabled || kind==2 || n==0 || n>64 || (kind==3 && !loaded)) rejected++;
            else predict(b,n);
          end
          'h018: if(t.data[8] && finished[t.data[0]]) pending[t.data[0]]=0;
          default: begin
            if(a>='h400 && a<='h43c) begin model[(a-'h400)/4]=t.data; loaded=0; end
            if(a>='h040 && a<='h04c) weights[(a-'h040)/4]=t.data;
            if(a>='h050 && a<='h05c) biases[(a-'h050)/4]=t.data;
          end
        endcase
      end else if(t.op==HOST_WRITE && a>='h1000 && a<'h2400) begin
        b=a/'h1000-1; v=(a%'h1000)/16; l=(a%16)/4;
        if(b>=0 && b<2 && v<64 && a%4==0 && !pending[b])
          for(int k=0;k<4;k++) if(t.enables[k]) inputs[b][v][l][8*k+:8]=t.data[8*k+:8];
      end else if(t.op==CPU_READ && a=='h008) begin
        finished[0]=t.response[16]; finished[1]=t.response[17];
      end else if(t.op==HOST_READ && a>='h3000 && a<'h7000) begin
        if(a<'h5000) begin b=a/'h1000-3; v=(a%'h1000)/16; l=(a%16)/4; end
        else begin b=a/'h1000-5; v=(a%'h1000)/4; l=0; end
        if(b<2 && v<counts[b] && pending[b] && finished[b]) begin
          if(t.response!==32'(expected[b][v][l]))
            `uvm_error("RESULT",$sformatf("bank=%0d row=%0d lane=%0d got=%h expected=%h",b,v,l,t.response,expected[b][v][l]))
          checked++;
        end else `uvm_error("OWNERSHIP","Result read without a completed owned job")
      end
    endfunction
    function void check_phase(uvm_phase phase);
      if(checked<271 || jobs<20 || rejected<3 || reset_busy<2)
        `uvm_error("INCOMPLETE",$sformatf("checked=%0d jobs=%0d rejected=%0d busy resets=%0d",checked,jobs,rejected,reset_busy))
      if(pending[0] || pending[1]) `uvm_error("OWNERSHIP","Unreleased job at end of test")
    endfunction
    function void report_phase(uvm_phase phase);
      `uvm_info("COUNTS",$sformatf("outputs=%0d jobs=%0d rejected=%0d busy_resets=%0d functional_coverage=%.2f%%",checked,jobs,rejected,reset_busy,jobs_cg.get_inst_coverage()),UVM_LOW)
    endfunction
  endclass

  class stream_sequence extends uvm_sequence #(stream_item);
    `uvm_object_utils(stream_sequence)
    bit [31:0] model[17],vectors[1084];
    int serial=1;
    function new(string name="stream_sequence"); super.new(name); endfunction
    task access_bus(bus_op op,int address=0,bit[31:0] data=0,int cycles=1,bit[3:0] enables=15);
      req=stream_item::type_id::create("request"); start_item(req);
      req.op=op; req.address=16'(address); req.data=data; req.cycles=cycles; req.enables=enables;
      finish_item(req);
    endtask
    task expect_read(int address,bit[31:0] expected,bit[31:0] mask='1);
      access_bus(CPU_READ,address);
      if((req.response&mask)!==(expected&mask))
        `uvm_error("REGISTER",$sformatf("addr=%h got=%h expected=%h mask=%h",address,req.response,expected,mask))
    endtask
    task setup_model();
      for(int i=0;i<16;i++) access_bus(CPU_WRITE,'h400+4*i,model[i+1]);
      access_bus(CPU_WRITE,'h03c,1); access_bus(CPU_WRITE,'h038,3);
      access_bus(CPU_WRITE,'h024,'h0e0e0e); access_bus(CPU_WRITE,'h030,'h10020);
    endtask
    task fill(int bank,int count,int offset=-1);
      for(int v=0;v<count;v++) for(int l=0;l<4;l++)
        access_bus(HOST_WRITE,'h1000+bank*'h1000+v*16+l*4,offset>=0 ? vectors[(offset+v)*4+l] : $urandom());
    endtask
    task submit(int bank,int count);
      access_bus(CPU_WRITE,'h010,(serial<<16)|(count<<8)|bank);
      access_bus(CPU_WRITE,'h014,1); serial++;
    endtask
    task collect(int bank,int count,int tag);
      bit done;
      done=0;
      for(int timeout=0;timeout<5000;timeout++) begin
        access_bus(CPU_READ,'h008);
        if(req.response[16+bank]===1'b1) begin done=1; break; end
      end
      if(!done) `uvm_fatal("TIMEOUT","Model did not complete")
      expect_read('h01c,32'(tag)<<(16*bank),32'hffff<<(16*bank));
      expect_read('h08c+bank*'h20,32'(count));
      expect_read('h090+bank*'h20,32'(count));
      for(int v=0;v<count;v++) begin
        for(int l=0;l<4;l++) access_bus(HOST_READ,'h3000+bank*'h1000+v*16+l*4);
        access_bus(HOST_READ,'h5000+bank*'h1000+v*4);
      end
      access_bus(CPU_WRITE,'h018,'h100|bank);
      expect_read('h008,0,32'h10100<<bank);
    endtask
    task body();
      int n,tag0,tag1;
      $readmemh("model.mem",model); $readmemh("inputs.mem",vectors);
      if(model[0]!=271) `uvm_fatal("VECTORS","Expected frozen 271-example test set")
      access_bus(RESET_BUS);
      expect_read(0,'h53545231); expect_read('h034,'h10007);

      access_bus(CPU_WRITE,'h038,3); submit(0,1); expect_read('h00c,1,1);
      expect_read('h008,0,'h30300); access_bus(CPU_WRITE,'h00c,'1);
      setup_model();
      submit(0,0); submit(1,65); expect_read('h00c,1,1); access_bus(CPU_WRITE,'h00c,'1);
      for(int start=0;start<271;start+=64) begin
        n=(271-start)>64 ? 64 : 271-start;
        fill((start/64)%2,n,start); tag0=serial; submit((start/64)%2,n);
        collect((start/64)%2,n,tag0);
      end

      fill(0,2,0); fill(1,2,2);
      tag0=serial; submit(0,2); tag1=serial; submit(1,2);
      submit(0,2); expect_read('h00c,1,1);
      access_bus(CPU_WRITE,'h018,'h100);
      expect_read('h008,'h300,'h300);
      access_bus(HOST_WRITE,'h1000,'hdeadbeef);
      expect_read('h00c,2,2); access_bus(CPU_WRITE,'h00c,'1);
      access_bus(CPU_WRITE,'h400,0); expect_read('h03c,0);
      collect(0,2,tag0); collect(1,2,tag1);
      setup_model();

      for(int delay_case=0;delay_case<2;delay_case++) begin
        fill(0,64,0); submit(0,64);
        access_bus(IDLE_BUS,0,0,delay_case==0 ? 20 : 180);
        access_bus(RESET_BUS); access_bus(IDLE_BUS,0,0,400);
        expect_read('h008,0,'h30300); expect_read('h03c,0); setup_model();
      end

      for(int trial=0;trial<32;trial++) begin
        int bank,kind,mode,scaling;
        bank=trial%2; kind=trial%3==0 ? 0 : (trial%3==1 ? 1 : 3); mode=(trial/2)%4;
        n=trial%4==0 ? 64 : (trial%4==1 ? 1 : (trial%4==2 ? 2 : 15));
        if(trial==31) n=7;
        for(int r=0;r<16;r++)
          access_bus(CPU_WRITE,'h400+4*r,(r/4)%2==1 && trial%2==0 ? $urandom_range(32768,0)-16384 : $urandom());
        access_bus(CPU_WRITE,'h03c,1);
        for(int r=0;r<4;r++) begin
          access_bus(CPU_WRITE,'h040+4*r,$urandom());
          access_bus(CPU_WRITE,'h050+4*r,trial%2==0 ? $urandom_range(32768,0)-16384 : $urandom());
        end
        scaling=kind==1 ? $urandom_range(31,0) : 0;
        access_bus(CPU_WRITE,'h038,32'(kind)|(scaling<<8)); access_bus(CPU_WRITE,'h020,1|(mode<<1));
        fill(bank,n);
        access_bus(HOST_WRITE,'h1000+bank*'h1000,$urandom(),1,4'b0101);
        tag0=serial; submit(bank,n); collect(bank,n,tag0);
      end

      access_bus(CPU_WRITE,'h020,0,1,1); expect_read('h00c,8,8);
      access_bus(HOST_WRITE,'h3000,1); expect_read('h00c,4,4);
      access_bus(CPU_WRITE,'h00c,'1); expect_read('h00c,0);

      access_bus(CPU_WRITE,'h020,0); submit(0,1); expect_read('h00c,1,1);
      access_bus(CPU_WRITE,'h020,1); access_bus(CPU_WRITE,'h038,2);
      submit(0,1); expect_read('h008,0,'h30300);
      access_bus(CPU_WRITE,'h00c,'1);
      expect_read('h004,'h00400004); expect_read('h020,1); expect_read('h038,2);
      expect_read('h024,'h0e0e0e); expect_read('h030,'h10020);
      expect_read('h070,'hbad00004); expect_read('h110,'hbad00004); expect_read('h10c,4,4);
      for(int r=0;r<4;r++) begin
        access_bus(CPU_WRITE,'h040+4*r,32'ha5a55a5a); expect_read('h040+4*r,32'ha5a55a5a);
        access_bus(CPU_WRITE,'h050+4*r,32'h80000001); expect_read('h050+4*r,32'h80000001);
        for(int a=0;a<16;a+=4) access_bus(CPU_READ,'h100+32*r+a);
      end
      access_bus(HOST_READ,0);
      if(req.response!==32'h53545231) `uvm_error("HOST_CSR","Host control mirror mismatch")
      access_bus(HOST_READ,'h7000);
      if(req.response!==32'hbad00004) `uvm_error("HOST_CSR","Invalid host read mismatch")
      access_bus(HOST_WRITE,'h1001,1); access_bus(HOST_WRITE,'h1400,1);
      expect_read('h00c,4,4); access_bus(CPU_WRITE,'h021,1); expect_read('h00c,8,8);
      access_bus(CPU_WRITE,'h00c,'1);

      for(int adaptive=0;adaptive<10;adaptive++) begin
        int configuration;
        access_bus(CPU_WRITE,'h038,0); access_bus(CPU_WRITE,'h020,1|((adaptive%2)<<1));
        configuration=adaptive==4 ? 'h020014 : (adaptive==5 ? 'hff0000 : (adaptive==0 ? 'h0eff00 : 'h0e1000));

        if(adaptive==6) configuration='h0e0c08;
        if(adaptive==7) configuration='h101010;
        if(adaptive==8) configuration='h100f0f;
        if(adaptive==9) configuration='h060606;
        access_bus(CPU_WRITE,'h024,32'(configuration));
        access_bus(CPU_WRITE,'h028,'h10000); expect_read('h028,'h10000);
        access_bus(CPU_WRITE,'h02c,adaptive%2 ? 'h10001 : 0); expect_read('h02c,adaptive%2 ? 'h10001 : 0);
        access_bus(CPU_WRITE,'h030,adaptive%2 ? 0 : 32);
        n=adaptive==0 ? 33 : 64;
        for(int v=0;v<n;v++) for(int l=0;l<4;l++)
          access_bus(HOST_WRITE,'h1000+(adaptive%2)*'h1000+v*16+l*4,32'(((v*4+l)%16-8)*12001));
        serial=adaptive%2 ? 'h5555 : 'haaaa;
        tag0=serial; submit(adaptive%2,n); collect(adaptive%2,n,tag0);
        for(int a=0;a<28;a+=4) access_bus(CPU_READ,'h080+(adaptive%2)*'h20+a);
      end

      access_bus(CPU_WRITE,'h038,0); access_bus(CPU_WRITE,'h020,7);
      for(int bank=0;bank<2;bank++) begin
        fill(bank,16);
        for(int mask=0;mask<16;mask++)
          for(int lane=0;lane<4;lane++)
            access_bus(HOST_WRITE,'h1000+bank*'h1000+mask*16+lane*4,
                       32'ha55ac33c^(32'(mask)<<16),1,4'(mask));
        tag0=serial; submit(bank,16); collect(bank,16,tag0);
      end
    endtask
  endclass

  class stream_env extends uvm_env;
    `uvm_component_utils(stream_env)
    uvm_sequencer #(stream_item) sequencer;
    stream_driver driver;
    stream_monitor monitor;
    stream_scoreboard scoreboard;
    function new(string name,uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sequencer=new("sequencer",this);
      driver=stream_driver::type_id::create("driver",this);
      monitor=stream_monitor::type_id::create("monitor",this);
      scoreboard=stream_scoreboard::type_id::create("scoreboard",this);
    endfunction
    function void connect_phase(uvm_phase phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
      monitor.observed.connect(scoreboard.observed);
    endfunction
  endclass

  class stream_model_test extends uvm_test;
    `uvm_component_utils(stream_model_test)
    stream_env env;
    function new(string name,uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase); env=stream_env::type_id::create("env",this);
    endfunction
    task run_phase(uvm_phase phase);
      stream_sequence sequence_h;
      phase.raise_objection(this);
      sequence_h=stream_sequence::type_id::create("sequence_h"); sequence_h.start(env.sequencer);
      phase.drop_objection(this);
    endtask
    function void report_phase(uvm_phase phase);
      uvm_report_server server;
      server=uvm_report_server::get_server();
      if(server.get_severity_count(UVM_ERROR)==0 && server.get_severity_count(UVM_FATAL)==0)
        `uvm_info("PASS","PASS stream_model_test",UVM_NONE)
    endfunction
  endclass
endpackage
