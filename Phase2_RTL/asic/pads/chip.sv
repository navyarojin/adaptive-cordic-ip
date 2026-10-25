module chip (
  input wire clk,
  input wire rst_n,
  input wire cpu_en_i,
  input wire cpu_we_i,
  input wire [3:0] cpu_be_i,
  input wire [11:0] cpu_addr_i,
  input wire [31:0] cpu_wdata_i,
  output wire [31:0] cpu_rdata_o,
  input wire ps_en_i,
  input wire [3:0] ps_we_i,
  input wire [15:0] ps_addr_i,
  input wire [31:0] ps_wdata_i,
  output wire [31:0] ps_rdata_o,
  output wire irq_o
);
  wire c_clk;
  wire c_rst_n;
  wire c_cpu_en_i;
  wire c_cpu_we_i;
  wire [3:0] c_cpu_be_i;
  wire [11:0] c_cpu_addr_i;
  wire [31:0] c_cpu_wdata_i;
  wire [31:0] c_cpu_rdata_o;
  wire c_ps_en_i;
  wire [3:0] c_ps_we_i;
  wire [15:0] c_ps_addr_i;
  wire [31:0] c_ps_wdata_i;
  wire [31:0] c_ps_rdata_o;
  wire c_irq_o;
  pc3c01 pad_clk (.CP(clk), .CLK(c_clk));
  pc3d01 pad_rst_n (.PAD(rst_n), .CIN(c_rst_n));
  pc3d01 pad_cpu_en_i (.PAD(cpu_en_i), .CIN(c_cpu_en_i));
  pc3d01 pad_cpu_we_i (.PAD(cpu_we_i), .CIN(c_cpu_we_i));
  pc3d01 pad_cpu_be_i_0 (.PAD(cpu_be_i[0]), .CIN(c_cpu_be_i[0]));
  pc3d01 pad_cpu_be_i_1 (.PAD(cpu_be_i[1]), .CIN(c_cpu_be_i[1]));
  pc3d01 pad_cpu_be_i_2 (.PAD(cpu_be_i[2]), .CIN(c_cpu_be_i[2]));
  pc3d01 pad_cpu_be_i_3 (.PAD(cpu_be_i[3]), .CIN(c_cpu_be_i[3]));
  pc3d01 pad_cpu_addr_i_0 (.PAD(cpu_addr_i[0]), .CIN(c_cpu_addr_i[0]));
  pc3d01 pad_cpu_addr_i_1 (.PAD(cpu_addr_i[1]), .CIN(c_cpu_addr_i[1]));
  pc3d01 pad_cpu_addr_i_2 (.PAD(cpu_addr_i[2]), .CIN(c_cpu_addr_i[2]));
  pc3d01 pad_cpu_addr_i_3 (.PAD(cpu_addr_i[3]), .CIN(c_cpu_addr_i[3]));
  pc3d01 pad_cpu_addr_i_4 (.PAD(cpu_addr_i[4]), .CIN(c_cpu_addr_i[4]));
  pc3d01 pad_cpu_addr_i_5 (.PAD(cpu_addr_i[5]), .CIN(c_cpu_addr_i[5]));
  pc3d01 pad_cpu_addr_i_6 (.PAD(cpu_addr_i[6]), .CIN(c_cpu_addr_i[6]));
  pc3d01 pad_cpu_addr_i_7 (.PAD(cpu_addr_i[7]), .CIN(c_cpu_addr_i[7]));
  pc3d01 pad_cpu_addr_i_8 (.PAD(cpu_addr_i[8]), .CIN(c_cpu_addr_i[8]));
  pc3d01 pad_cpu_addr_i_9 (.PAD(cpu_addr_i[9]), .CIN(c_cpu_addr_i[9]));
  pc3d01 pad_cpu_addr_i_10 (.PAD(cpu_addr_i[10]), .CIN(c_cpu_addr_i[10]));
  pc3d01 pad_cpu_addr_i_11 (.PAD(cpu_addr_i[11]), .CIN(c_cpu_addr_i[11]));
  pc3d01 pad_cpu_wdata_i_0 (.PAD(cpu_wdata_i[0]), .CIN(c_cpu_wdata_i[0]));
  pc3d01 pad_cpu_wdata_i_1 (.PAD(cpu_wdata_i[1]), .CIN(c_cpu_wdata_i[1]));
  pc3d01 pad_cpu_wdata_i_2 (.PAD(cpu_wdata_i[2]), .CIN(c_cpu_wdata_i[2]));
  pc3d01 pad_cpu_wdata_i_3 (.PAD(cpu_wdata_i[3]), .CIN(c_cpu_wdata_i[3]));
  pc3d01 pad_cpu_wdata_i_4 (.PAD(cpu_wdata_i[4]), .CIN(c_cpu_wdata_i[4]));
  pc3d01 pad_cpu_wdata_i_5 (.PAD(cpu_wdata_i[5]), .CIN(c_cpu_wdata_i[5]));
  pc3d01 pad_cpu_wdata_i_6 (.PAD(cpu_wdata_i[6]), .CIN(c_cpu_wdata_i[6]));
  pc3d01 pad_cpu_wdata_i_7 (.PAD(cpu_wdata_i[7]), .CIN(c_cpu_wdata_i[7]));
  pc3d01 pad_cpu_wdata_i_8 (.PAD(cpu_wdata_i[8]), .CIN(c_cpu_wdata_i[8]));
  pc3d01 pad_cpu_wdata_i_9 (.PAD(cpu_wdata_i[9]), .CIN(c_cpu_wdata_i[9]));
  pc3d01 pad_cpu_wdata_i_10 (.PAD(cpu_wdata_i[10]), .CIN(c_cpu_wdata_i[10]));
  pc3d01 pad_cpu_wdata_i_11 (.PAD(cpu_wdata_i[11]), .CIN(c_cpu_wdata_i[11]));
  pc3d01 pad_cpu_wdata_i_12 (.PAD(cpu_wdata_i[12]), .CIN(c_cpu_wdata_i[12]));
  pc3d01 pad_cpu_wdata_i_13 (.PAD(cpu_wdata_i[13]), .CIN(c_cpu_wdata_i[13]));
  pc3d01 pad_cpu_wdata_i_14 (.PAD(cpu_wdata_i[14]), .CIN(c_cpu_wdata_i[14]));
  pc3d01 pad_cpu_wdata_i_15 (.PAD(cpu_wdata_i[15]), .CIN(c_cpu_wdata_i[15]));
  pc3d01 pad_cpu_wdata_i_16 (.PAD(cpu_wdata_i[16]), .CIN(c_cpu_wdata_i[16]));
  pc3d01 pad_cpu_wdata_i_17 (.PAD(cpu_wdata_i[17]), .CIN(c_cpu_wdata_i[17]));
  pc3d01 pad_cpu_wdata_i_18 (.PAD(cpu_wdata_i[18]), .CIN(c_cpu_wdata_i[18]));
  pc3d01 pad_cpu_wdata_i_19 (.PAD(cpu_wdata_i[19]), .CIN(c_cpu_wdata_i[19]));
  pc3d01 pad_cpu_wdata_i_20 (.PAD(cpu_wdata_i[20]), .CIN(c_cpu_wdata_i[20]));
  pc3d01 pad_cpu_wdata_i_21 (.PAD(cpu_wdata_i[21]), .CIN(c_cpu_wdata_i[21]));
  pc3d01 pad_cpu_wdata_i_22 (.PAD(cpu_wdata_i[22]), .CIN(c_cpu_wdata_i[22]));
  pc3d01 pad_cpu_wdata_i_23 (.PAD(cpu_wdata_i[23]), .CIN(c_cpu_wdata_i[23]));
  pc3d01 pad_cpu_wdata_i_24 (.PAD(cpu_wdata_i[24]), .CIN(c_cpu_wdata_i[24]));
  pc3d01 pad_cpu_wdata_i_25 (.PAD(cpu_wdata_i[25]), .CIN(c_cpu_wdata_i[25]));
  pc3d01 pad_cpu_wdata_i_26 (.PAD(cpu_wdata_i[26]), .CIN(c_cpu_wdata_i[26]));
  pc3d01 pad_cpu_wdata_i_27 (.PAD(cpu_wdata_i[27]), .CIN(c_cpu_wdata_i[27]));
  pc3d01 pad_cpu_wdata_i_28 (.PAD(cpu_wdata_i[28]), .CIN(c_cpu_wdata_i[28]));
  pc3d01 pad_cpu_wdata_i_29 (.PAD(cpu_wdata_i[29]), .CIN(c_cpu_wdata_i[29]));
  pc3d01 pad_cpu_wdata_i_30 (.PAD(cpu_wdata_i[30]), .CIN(c_cpu_wdata_i[30]));
  pc3d01 pad_cpu_wdata_i_31 (.PAD(cpu_wdata_i[31]), .CIN(c_cpu_wdata_i[31]));
  pc3o05 pad_cpu_rdata_o_0 (.I(c_cpu_rdata_o[0]), .PAD(cpu_rdata_o[0]));
  pc3o05 pad_cpu_rdata_o_1 (.I(c_cpu_rdata_o[1]), .PAD(cpu_rdata_o[1]));
  pc3o05 pad_cpu_rdata_o_2 (.I(c_cpu_rdata_o[2]), .PAD(cpu_rdata_o[2]));
  pc3o05 pad_cpu_rdata_o_3 (.I(c_cpu_rdata_o[3]), .PAD(cpu_rdata_o[3]));
  pc3o05 pad_cpu_rdata_o_4 (.I(c_cpu_rdata_o[4]), .PAD(cpu_rdata_o[4]));
  pc3o05 pad_cpu_rdata_o_5 (.I(c_cpu_rdata_o[5]), .PAD(cpu_rdata_o[5]));
  pc3o05 pad_cpu_rdata_o_6 (.I(c_cpu_rdata_o[6]), .PAD(cpu_rdata_o[6]));
  pc3o05 pad_cpu_rdata_o_7 (.I(c_cpu_rdata_o[7]), .PAD(cpu_rdata_o[7]));
  pc3o05 pad_cpu_rdata_o_8 (.I(c_cpu_rdata_o[8]), .PAD(cpu_rdata_o[8]));
  pc3o05 pad_cpu_rdata_o_9 (.I(c_cpu_rdata_o[9]), .PAD(cpu_rdata_o[9]));
  pc3o05 pad_cpu_rdata_o_10 (.I(c_cpu_rdata_o[10]), .PAD(cpu_rdata_o[10]));
  pc3o05 pad_cpu_rdata_o_11 (.I(c_cpu_rdata_o[11]), .PAD(cpu_rdata_o[11]));
  pc3o05 pad_cpu_rdata_o_12 (.I(c_cpu_rdata_o[12]), .PAD(cpu_rdata_o[12]));
  pc3o05 pad_cpu_rdata_o_13 (.I(c_cpu_rdata_o[13]), .PAD(cpu_rdata_o[13]));
  pc3o05 pad_cpu_rdata_o_14 (.I(c_cpu_rdata_o[14]), .PAD(cpu_rdata_o[14]));
  pc3o05 pad_cpu_rdata_o_15 (.I(c_cpu_rdata_o[15]), .PAD(cpu_rdata_o[15]));
  pc3o05 pad_cpu_rdata_o_16 (.I(c_cpu_rdata_o[16]), .PAD(cpu_rdata_o[16]));
  pc3o05 pad_cpu_rdata_o_17 (.I(c_cpu_rdata_o[17]), .PAD(cpu_rdata_o[17]));
  pc3o05 pad_cpu_rdata_o_18 (.I(c_cpu_rdata_o[18]), .PAD(cpu_rdata_o[18]));
  pc3o05 pad_cpu_rdata_o_19 (.I(c_cpu_rdata_o[19]), .PAD(cpu_rdata_o[19]));
  pc3o05 pad_cpu_rdata_o_20 (.I(c_cpu_rdata_o[20]), .PAD(cpu_rdata_o[20]));
  pc3o05 pad_cpu_rdata_o_21 (.I(c_cpu_rdata_o[21]), .PAD(cpu_rdata_o[21]));
  pc3o05 pad_cpu_rdata_o_22 (.I(c_cpu_rdata_o[22]), .PAD(cpu_rdata_o[22]));
  pc3o05 pad_cpu_rdata_o_23 (.I(c_cpu_rdata_o[23]), .PAD(cpu_rdata_o[23]));
  pc3o05 pad_cpu_rdata_o_24 (.I(c_cpu_rdata_o[24]), .PAD(cpu_rdata_o[24]));
  pc3o05 pad_cpu_rdata_o_25 (.I(c_cpu_rdata_o[25]), .PAD(cpu_rdata_o[25]));
  pc3o05 pad_cpu_rdata_o_26 (.I(c_cpu_rdata_o[26]), .PAD(cpu_rdata_o[26]));
  pc3o05 pad_cpu_rdata_o_27 (.I(c_cpu_rdata_o[27]), .PAD(cpu_rdata_o[27]));
  pc3o05 pad_cpu_rdata_o_28 (.I(c_cpu_rdata_o[28]), .PAD(cpu_rdata_o[28]));
  pc3o05 pad_cpu_rdata_o_29 (.I(c_cpu_rdata_o[29]), .PAD(cpu_rdata_o[29]));
  pc3o05 pad_cpu_rdata_o_30 (.I(c_cpu_rdata_o[30]), .PAD(cpu_rdata_o[30]));
  pc3o05 pad_cpu_rdata_o_31 (.I(c_cpu_rdata_o[31]), .PAD(cpu_rdata_o[31]));
  pc3d01 pad_ps_en_i (.PAD(ps_en_i), .CIN(c_ps_en_i));
  pc3d01 pad_ps_we_i_0 (.PAD(ps_we_i[0]), .CIN(c_ps_we_i[0]));
  pc3d01 pad_ps_we_i_1 (.PAD(ps_we_i[1]), .CIN(c_ps_we_i[1]));
  pc3d01 pad_ps_we_i_2 (.PAD(ps_we_i[2]), .CIN(c_ps_we_i[2]));
  pc3d01 pad_ps_we_i_3 (.PAD(ps_we_i[3]), .CIN(c_ps_we_i[3]));
  pc3d01 pad_ps_addr_i_0 (.PAD(ps_addr_i[0]), .CIN(c_ps_addr_i[0]));
  pc3d01 pad_ps_addr_i_1 (.PAD(ps_addr_i[1]), .CIN(c_ps_addr_i[1]));
  pc3d01 pad_ps_addr_i_2 (.PAD(ps_addr_i[2]), .CIN(c_ps_addr_i[2]));
  pc3d01 pad_ps_addr_i_3 (.PAD(ps_addr_i[3]), .CIN(c_ps_addr_i[3]));
  pc3d01 pad_ps_addr_i_4 (.PAD(ps_addr_i[4]), .CIN(c_ps_addr_i[4]));
  pc3d01 pad_ps_addr_i_5 (.PAD(ps_addr_i[5]), .CIN(c_ps_addr_i[5]));
  pc3d01 pad_ps_addr_i_6 (.PAD(ps_addr_i[6]), .CIN(c_ps_addr_i[6]));
  pc3d01 pad_ps_addr_i_7 (.PAD(ps_addr_i[7]), .CIN(c_ps_addr_i[7]));
  pc3d01 pad_ps_addr_i_8 (.PAD(ps_addr_i[8]), .CIN(c_ps_addr_i[8]));
  pc3d01 pad_ps_addr_i_9 (.PAD(ps_addr_i[9]), .CIN(c_ps_addr_i[9]));
  pc3d01 pad_ps_addr_i_10 (.PAD(ps_addr_i[10]), .CIN(c_ps_addr_i[10]));
  pc3d01 pad_ps_addr_i_11 (.PAD(ps_addr_i[11]), .CIN(c_ps_addr_i[11]));
  pc3d01 pad_ps_addr_i_12 (.PAD(ps_addr_i[12]), .CIN(c_ps_addr_i[12]));
  pc3d01 pad_ps_addr_i_13 (.PAD(ps_addr_i[13]), .CIN(c_ps_addr_i[13]));
  pc3d01 pad_ps_addr_i_14 (.PAD(ps_addr_i[14]), .CIN(c_ps_addr_i[14]));
  pc3d01 pad_ps_addr_i_15 (.PAD(ps_addr_i[15]), .CIN(c_ps_addr_i[15]));
  pc3d01 pad_ps_wdata_i_0 (.PAD(ps_wdata_i[0]), .CIN(c_ps_wdata_i[0]));
  pc3d01 pad_ps_wdata_i_1 (.PAD(ps_wdata_i[1]), .CIN(c_ps_wdata_i[1]));
  pc3d01 pad_ps_wdata_i_2 (.PAD(ps_wdata_i[2]), .CIN(c_ps_wdata_i[2]));
  pc3d01 pad_ps_wdata_i_3 (.PAD(ps_wdata_i[3]), .CIN(c_ps_wdata_i[3]));
  pc3d01 pad_ps_wdata_i_4 (.PAD(ps_wdata_i[4]), .CIN(c_ps_wdata_i[4]));
  pc3d01 pad_ps_wdata_i_5 (.PAD(ps_wdata_i[5]), .CIN(c_ps_wdata_i[5]));
  pc3d01 pad_ps_wdata_i_6 (.PAD(ps_wdata_i[6]), .CIN(c_ps_wdata_i[6]));
  pc3d01 pad_ps_wdata_i_7 (.PAD(ps_wdata_i[7]), .CIN(c_ps_wdata_i[7]));
  pc3d01 pad_ps_wdata_i_8 (.PAD(ps_wdata_i[8]), .CIN(c_ps_wdata_i[8]));
  pc3d01 pad_ps_wdata_i_9 (.PAD(ps_wdata_i[9]), .CIN(c_ps_wdata_i[9]));
  pc3d01 pad_ps_wdata_i_10 (.PAD(ps_wdata_i[10]), .CIN(c_ps_wdata_i[10]));
  pc3d01 pad_ps_wdata_i_11 (.PAD(ps_wdata_i[11]), .CIN(c_ps_wdata_i[11]));
  pc3d01 pad_ps_wdata_i_12 (.PAD(ps_wdata_i[12]), .CIN(c_ps_wdata_i[12]));
  pc3d01 pad_ps_wdata_i_13 (.PAD(ps_wdata_i[13]), .CIN(c_ps_wdata_i[13]));
  pc3d01 pad_ps_wdata_i_14 (.PAD(ps_wdata_i[14]), .CIN(c_ps_wdata_i[14]));
  pc3d01 pad_ps_wdata_i_15 (.PAD(ps_wdata_i[15]), .CIN(c_ps_wdata_i[15]));
  pc3d01 pad_ps_wdata_i_16 (.PAD(ps_wdata_i[16]), .CIN(c_ps_wdata_i[16]));
  pc3d01 pad_ps_wdata_i_17 (.PAD(ps_wdata_i[17]), .CIN(c_ps_wdata_i[17]));
  pc3d01 pad_ps_wdata_i_18 (.PAD(ps_wdata_i[18]), .CIN(c_ps_wdata_i[18]));
  pc3d01 pad_ps_wdata_i_19 (.PAD(ps_wdata_i[19]), .CIN(c_ps_wdata_i[19]));
  pc3d01 pad_ps_wdata_i_20 (.PAD(ps_wdata_i[20]), .CIN(c_ps_wdata_i[20]));
  pc3d01 pad_ps_wdata_i_21 (.PAD(ps_wdata_i[21]), .CIN(c_ps_wdata_i[21]));
  pc3d01 pad_ps_wdata_i_22 (.PAD(ps_wdata_i[22]), .CIN(c_ps_wdata_i[22]));
  pc3d01 pad_ps_wdata_i_23 (.PAD(ps_wdata_i[23]), .CIN(c_ps_wdata_i[23]));
  pc3d01 pad_ps_wdata_i_24 (.PAD(ps_wdata_i[24]), .CIN(c_ps_wdata_i[24]));
  pc3d01 pad_ps_wdata_i_25 (.PAD(ps_wdata_i[25]), .CIN(c_ps_wdata_i[25]));
  pc3d01 pad_ps_wdata_i_26 (.PAD(ps_wdata_i[26]), .CIN(c_ps_wdata_i[26]));
  pc3d01 pad_ps_wdata_i_27 (.PAD(ps_wdata_i[27]), .CIN(c_ps_wdata_i[27]));
  pc3d01 pad_ps_wdata_i_28 (.PAD(ps_wdata_i[28]), .CIN(c_ps_wdata_i[28]));
  pc3d01 pad_ps_wdata_i_29 (.PAD(ps_wdata_i[29]), .CIN(c_ps_wdata_i[29]));
  pc3d01 pad_ps_wdata_i_30 (.PAD(ps_wdata_i[30]), .CIN(c_ps_wdata_i[30]));
  pc3d01 pad_ps_wdata_i_31 (.PAD(ps_wdata_i[31]), .CIN(c_ps_wdata_i[31]));
  pc3o05 pad_ps_rdata_o_0 (.I(c_ps_rdata_o[0]), .PAD(ps_rdata_o[0]));
  pc3o05 pad_ps_rdata_o_1 (.I(c_ps_rdata_o[1]), .PAD(ps_rdata_o[1]));
  pc3o05 pad_ps_rdata_o_2 (.I(c_ps_rdata_o[2]), .PAD(ps_rdata_o[2]));
  pc3o05 pad_ps_rdata_o_3 (.I(c_ps_rdata_o[3]), .PAD(ps_rdata_o[3]));
  pc3o05 pad_ps_rdata_o_4 (.I(c_ps_rdata_o[4]), .PAD(ps_rdata_o[4]));
  pc3o05 pad_ps_rdata_o_5 (.I(c_ps_rdata_o[5]), .PAD(ps_rdata_o[5]));
  pc3o05 pad_ps_rdata_o_6 (.I(c_ps_rdata_o[6]), .PAD(ps_rdata_o[6]));
  pc3o05 pad_ps_rdata_o_7 (.I(c_ps_rdata_o[7]), .PAD(ps_rdata_o[7]));
  pc3o05 pad_ps_rdata_o_8 (.I(c_ps_rdata_o[8]), .PAD(ps_rdata_o[8]));
  pc3o05 pad_ps_rdata_o_9 (.I(c_ps_rdata_o[9]), .PAD(ps_rdata_o[9]));
  pc3o05 pad_ps_rdata_o_10 (.I(c_ps_rdata_o[10]), .PAD(ps_rdata_o[10]));
  pc3o05 pad_ps_rdata_o_11 (.I(c_ps_rdata_o[11]), .PAD(ps_rdata_o[11]));
  pc3o05 pad_ps_rdata_o_12 (.I(c_ps_rdata_o[12]), .PAD(ps_rdata_o[12]));
  pc3o05 pad_ps_rdata_o_13 (.I(c_ps_rdata_o[13]), .PAD(ps_rdata_o[13]));
  pc3o05 pad_ps_rdata_o_14 (.I(c_ps_rdata_o[14]), .PAD(ps_rdata_o[14]));
  pc3o05 pad_ps_rdata_o_15 (.I(c_ps_rdata_o[15]), .PAD(ps_rdata_o[15]));
  pc3o05 pad_ps_rdata_o_16 (.I(c_ps_rdata_o[16]), .PAD(ps_rdata_o[16]));
  pc3o05 pad_ps_rdata_o_17 (.I(c_ps_rdata_o[17]), .PAD(ps_rdata_o[17]));
  pc3o05 pad_ps_rdata_o_18 (.I(c_ps_rdata_o[18]), .PAD(ps_rdata_o[18]));
  pc3o05 pad_ps_rdata_o_19 (.I(c_ps_rdata_o[19]), .PAD(ps_rdata_o[19]));
  pc3o05 pad_ps_rdata_o_20 (.I(c_ps_rdata_o[20]), .PAD(ps_rdata_o[20]));
  pc3o05 pad_ps_rdata_o_21 (.I(c_ps_rdata_o[21]), .PAD(ps_rdata_o[21]));
  pc3o05 pad_ps_rdata_o_22 (.I(c_ps_rdata_o[22]), .PAD(ps_rdata_o[22]));
  pc3o05 pad_ps_rdata_o_23 (.I(c_ps_rdata_o[23]), .PAD(ps_rdata_o[23]));
  pc3o05 pad_ps_rdata_o_24 (.I(c_ps_rdata_o[24]), .PAD(ps_rdata_o[24]));
  pc3o05 pad_ps_rdata_o_25 (.I(c_ps_rdata_o[25]), .PAD(ps_rdata_o[25]));
  pc3o05 pad_ps_rdata_o_26 (.I(c_ps_rdata_o[26]), .PAD(ps_rdata_o[26]));
  pc3o05 pad_ps_rdata_o_27 (.I(c_ps_rdata_o[27]), .PAD(ps_rdata_o[27]));
  pc3o05 pad_ps_rdata_o_28 (.I(c_ps_rdata_o[28]), .PAD(ps_rdata_o[28]));
  pc3o05 pad_ps_rdata_o_29 (.I(c_ps_rdata_o[29]), .PAD(ps_rdata_o[29]));
  pc3o05 pad_ps_rdata_o_30 (.I(c_ps_rdata_o[30]), .PAD(ps_rdata_o[30]));
  pc3o05 pad_ps_rdata_o_31 (.I(c_ps_rdata_o[31]), .PAD(ps_rdata_o[31]));
  pc3o05 pad_irq_o (.I(c_irq_o), .PAD(irq_o));
  stream_mmio #(.LANES(4)) u_core (
    .clk(c_clk),
    .rst_n(c_rst_n),
    .cpu_en_i(c_cpu_en_i),
    .cpu_we_i(c_cpu_we_i),
    .cpu_be_i(c_cpu_be_i),
    .cpu_addr_i(c_cpu_addr_i),
    .cpu_wdata_i(c_cpu_wdata_i),
    .cpu_rdata_o(c_cpu_rdata_o),
    .ps_en_i(c_ps_en_i),
    .ps_we_i(c_ps_we_i),
    .ps_addr_i(c_ps_addr_i),
    .ps_wdata_i(c_ps_wdata_i),
    .ps_rdata_o(c_ps_rdata_o),
    .irq_o(c_irq_o)
  );
endmodule
