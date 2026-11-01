interface tcdm_if(input logic clk, rst_n);
  logic active = 0;
  logic reset_request = 0;
  logic core_start, sample_mode;
  logic [4:0] budget;
  int last_budget;
  bit last_sample;
  always @(posedge clk) begin
    if (!rst_n) begin
      last_budget <= 0;
      last_sample <= 0;
    end else if (core_start) begin
      last_budget <= int'(budget);
      last_sample <= sample_mode;
    end
  end
  logic req = 0;
  logic wen = 1;
  logic [31:0] addr = 0, wdata = 0;
  logic [3:0] be = 4'hf;
  logic gnt, rvalid, error, irq;
  logic [31:0] rdata;

  task automatic transfer(input bit write, input logic [31:0] address, data,
      output logic [31:0] response, output logic failed,
      input logic [3:0] byte_enable = 4'hf);
    int timeout;
    @(negedge clk);
    req = 1;
    wen = !write;
    addr = address;
    wdata = data;
    be = byte_enable;
    timeout = 0;
    do begin
      @(posedge clk);
      timeout++;
      if (timeout > 1024) $fatal(1,"TCDM grant timeout");
    end while (!gnt);
    @(negedge clk);
    req = 0;
    timeout = 0;
    while (!rvalid) begin
      @(negedge clk);
      timeout++;
      if (timeout > 1024) $fatal(1,"TCDM response timeout");
    end
    response = rdata;
    failed = error;
  endtask

  property held_request;
    @(posedge clk) disable iff (!rst_n)
      req && !gnt |=> req && $stable({wen,addr,wdata,be});
  endproperty
  assert property (held_request) else $error("TCDM request changed before grant");
endinterface
