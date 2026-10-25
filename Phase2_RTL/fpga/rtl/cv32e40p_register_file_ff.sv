module cv32e40p_register_file #(
    parameter ADDR_WIDTH = 5,
    parameter DATA_WIDTH = 32,
    parameter FPU        = 0,
    parameter ZFINX      = 0
) (

    input logic clk,
    input logic rst_n,

    input logic scan_cg_en_i,

    input  logic [ADDR_WIDTH-1:0] raddr_a_i,
    output logic [DATA_WIDTH-1:0] rdata_a_o,

    input  logic [ADDR_WIDTH-1:0] raddr_b_i,
    output logic [DATA_WIDTH-1:0] rdata_b_o,

    input  logic [ADDR_WIDTH-1:0] raddr_c_i,
    output logic [DATA_WIDTH-1:0] rdata_c_o,

    input logic [ADDR_WIDTH-1:0] waddr_a_i,
    input logic [DATA_WIDTH-1:0] wdata_a_i,
    input logic                  we_a_i,

    input logic [ADDR_WIDTH-1:0] waddr_b_i,
    input logic [DATA_WIDTH-1:0] wdata_b_i,
    input logic                  we_b_i
);

  localparam NUM_WORDS = 2 ** (ADDR_WIDTH - 1);

  localparam NUM_FP_WORDS = 2 ** (ADDR_WIDTH - 1);
  localparam NUM_TOT_WORDS = FPU ? (ZFINX ? NUM_WORDS : NUM_WORDS + NUM_FP_WORDS) : NUM_WORDS;

  logic [    NUM_WORDS-1:0][DATA_WIDTH-1:0] mem;

  logic [ NUM_FP_WORDS-1:0][DATA_WIDTH-1:0] mem_fp;

  logic [   ADDR_WIDTH-1:0]                 waddr_a;
  logic [   ADDR_WIDTH-1:0]                 waddr_b;

  logic [NUM_TOT_WORDS-1:0]                 we_a_dec;
  logic [NUM_TOT_WORDS-1:0]                 we_b_dec;

  assign rdata_a_o = raddr_a_i[5] ? mem_fp[raddr_a_i[4:0]] : mem[raddr_a_i[4:0]];
  assign rdata_b_o = raddr_b_i[5] ? mem_fp[raddr_b_i[4:0]] : mem[raddr_b_i[4:0]];
  assign rdata_c_o = raddr_c_i[5] ? mem_fp[raddr_c_i[4:0]] : mem[raddr_c_i[4:0]];

  assign waddr_a   = waddr_a_i;
  assign waddr_b   = waddr_b_i;

  genvar gidx;
  generate
    for (gidx = 0; gidx < NUM_TOT_WORDS; gidx++) begin : gen_we_decoder
      assign we_a_dec[gidx] = (waddr_a == gidx) ? we_a_i : 1'b0;
      assign we_b_dec[gidx] = (waddr_b == gidx) ? we_b_i : 1'b0;
    end
  endgenerate

  genvar i, l;
  generate

    always_ff @(posedge clk or negedge rst_n) begin
      if (~rst_n) begin

        mem[0] <= 32'b0;
      end else begin

        mem[0] <= 32'b0;
      end
    end

    for (i = 1; i < NUM_WORDS; i++) begin : gen_rf

      always_ff @(posedge clk, negedge rst_n) begin : register_write_behavioral
        if (rst_n == 1'b0) begin
          mem[i] <= 32'b0;
        end else begin
          if (we_b_dec[i] == 1'b1) mem[i] <= wdata_b_i;
          else if (we_a_dec[i] == 1'b1) mem[i] <= wdata_a_i;
        end
      end

    end

    if (FPU == 1 && ZFINX == 0) begin : gen_mem_fp_write

      for (l = 0; l < NUM_FP_WORDS; l++) begin
        always_ff @(posedge clk, negedge rst_n) begin : fp_regs
          if (rst_n == 1'b0) mem_fp[l] <= '0;
          else if (we_b_dec[l+NUM_WORDS] == 1'b1) mem_fp[l] <= wdata_b_i;
          else if (we_a_dec[l+NUM_WORDS] == 1'b1) mem_fp[l] <= wdata_a_i;
        end
      end
    end else begin : gen_no_mem_fp_write
      assign mem_fp = 'b0;
    end

  endgenerate

endmodule
