module cv32e40p_decoder
  import cv32e40p_pkg::*;
  import cv32e40p_apu_core_pkg::*;
  import cv32e40p_fpu_pkg::*;
#(
  parameter COREV_PULP        = 1,
  parameter COREV_CLUSTER     = 0,
  parameter A_EXTENSION       = 0,
  parameter FPU               = 0,
  parameter FPU_ADDMUL_LAT    = 0,
  parameter FPU_OTHERS_LAT    = 0,
  parameter ZFINX             = 0,
  parameter PULP_SECURE       = 0,
  parameter USE_PMP           = 0,
  parameter APU_WOP_CPU       = 6,
  parameter DEBUG_TRIGGER_EN  = 1
)
(

  input  logic        deassert_we_i,

  output logic        illegal_insn_o,
  output logic        ebrk_insn_o,

  output logic        mret_insn_o,
  output logic        uret_insn_o,
  output logic        dret_insn_o,

  output logic        mret_dec_o,
  output logic        uret_dec_o,
  output logic        dret_dec_o,

  output logic        ecall_insn_o,
  output logic        wfi_o       ,

  output logic        fencei_insn_o,

  output logic        rega_used_o,
  output logic        regb_used_o,
  output logic        regc_used_o,

  output logic        reg_fp_a_o,
  output logic        reg_fp_b_o,
  output logic        reg_fp_c_o,
  output logic        reg_fp_d_o,

  output logic [ 0:0] bmask_a_mux_o,
  output logic [ 1:0] bmask_b_mux_o,
  output logic        alu_bmask_a_mux_sel_o,
  output logic        alu_bmask_b_mux_sel_o,

  input  logic [31:0] instr_rdata_i,
  input  logic        illegal_c_insn_i,

  output logic        alu_en_o,
  output alu_opcode_e alu_operator_o,
  output logic [2:0]  alu_op_a_mux_sel_o,
  output logic [2:0]  alu_op_b_mux_sel_o,
  output logic [1:0]  alu_op_c_mux_sel_o,
  output logic        alu_vec_o,
  output logic [1:0]  alu_vec_mode_o,
  output logic        scalar_replication_o,
  output logic        scalar_replication_c_o,
  output logic [0:0]  imm_a_mux_sel_o,
  output logic [3:0]  imm_b_mux_sel_o,
  output logic [1:0]  regc_mux_o,
  output logic        is_clpx_o,
  output logic        is_subrot_o,

  output mul_opcode_e mult_operator_o,
  output logic        mult_int_en_o,
  output logic        mult_dot_en_o,
  output logic [0:0]  mult_imm_mux_o,
  output logic        mult_sel_subword_o,
  output logic [1:0]  mult_signed_mode_o,
  output logic [1:0]  mult_dot_signed_o,

  input  logic            fs_off_i,
  input  logic [C_RM-1:0] frm_i,

  output logic [cv32e40p_fpu_pkg::FP_FORMAT_BITS-1:0]  fpu_dst_fmt_o,
  output logic [cv32e40p_fpu_pkg::FP_FORMAT_BITS-1:0]  fpu_src_fmt_o,
  output logic [cv32e40p_fpu_pkg::INT_FORMAT_BITS-1:0] fpu_int_fmt_o,

  output logic                   apu_en_o,
  output logic [APU_WOP_CPU-1:0] apu_op_o,
  output logic [1:0]             apu_lat_o,
  output logic [2:0]             fp_rnd_mode_o,

  output logic        regfile_mem_we_o,
  output logic        regfile_alu_we_o,
  output logic        regfile_alu_we_dec_o,
  output logic        regfile_alu_waddr_sel_o,

  output logic        csr_access_o,
  output logic        csr_status_o,
  output csr_opcode_e csr_op_o,
  input  PrivLvl_t    current_priv_lvl_i,

  output logic        data_req_o,
  output logic        data_we_o,
  output logic        prepost_useincr_o,
  output logic [1:0]  data_type_o,
  output logic [1:0]  data_sign_extension_o,
  output logic [1:0]  data_reg_offset_o,
  output logic        data_load_event_o,

  output logic [5:0] atop_o,

  output logic [2:0]  hwlp_we_o,
  output logic [1:0]  hwlp_target_mux_sel_o,
  output logic [1:0]  hwlp_start_mux_sel_o,
  output logic        hwlp_cnt_mux_sel_o,

  input  logic        debug_mode_i,
  input  logic        debug_wfi_no_sleep_i,

  output logic [1:0]  ctrl_transfer_insn_in_dec_o,
  output logic [1:0]  ctrl_transfer_insn_in_id_o,
  output logic [1:0]  ctrl_transfer_target_mux_sel_o,

  input  logic [31:0] mcounteren_i
);

  logic       regfile_mem_we;
  logic       regfile_alu_we;
  logic       data_req;
  logic [2:0] hwlp_we;
  logic       csr_illegal;
  logic [1:0] ctrl_transfer_insn;

  csr_opcode_e csr_op;

  logic       alu_en;
  logic       mult_int_en;
  logic       mult_dot_en;
  logic       apu_en;

  logic check_fprm;

  logic [cv32e40p_fpu_pkg::OP_BITS-1:0] fpu_op;
  logic                                 fpu_op_mod;
  logic                                 fpu_vec_op;

  enum logic[1:0] {ADDMUL, DIVSQRT, NONCOMP, CONV} fp_op_group;

  always_comb
  begin: instruction_decoder
    ctrl_transfer_insn             = BRANCH_NONE;
    ctrl_transfer_target_mux_sel_o = JT_JAL;

    alu_en                         = 1'b1;
    alu_operator_o                 = ALU_SLTU;
    alu_op_a_mux_sel_o             = OP_A_REGA_OR_FWD;
    alu_op_b_mux_sel_o             = OP_B_REGB_OR_FWD;
    alu_op_c_mux_sel_o             = OP_C_REGC_OR_FWD;
    alu_vec_o                      = 1'b0;
    alu_vec_mode_o                 = VEC_MODE32;
    scalar_replication_o           = 1'b0;
    scalar_replication_c_o         = 1'b0;
    regc_mux_o                     = REGC_ZERO;
    imm_a_mux_sel_o                = IMMA_ZERO;
    imm_b_mux_sel_o                = IMMB_I;

    mult_int_en                    = 1'b0;
    mult_dot_en                    = 1'b0;
    mult_operator_o                = MUL_I;
    mult_imm_mux_o                 = MIMM_ZERO;
    mult_signed_mode_o             = 2'b00;
    mult_sel_subword_o             = 1'b0;
    mult_dot_signed_o              = 2'b00;

    apu_en                         = 1'b0;
    apu_op_o                       = '0;
    apu_lat_o                      = '0;
    fp_rnd_mode_o                  = '0;
    fpu_op                         = cv32e40p_fpu_pkg::SGNJ;
    fpu_op_mod                     = 1'b0;
    fpu_vec_op                     = 1'b0;
    fpu_dst_fmt_o                  = cv32e40p_fpu_pkg::FP32;
    fpu_src_fmt_o                  = cv32e40p_fpu_pkg::FP32;
    fpu_int_fmt_o                  = cv32e40p_fpu_pkg::INT32;
    check_fprm                     = 1'b0;
    fp_op_group                    = ADDMUL;

    regfile_mem_we                 = 1'b0;
    regfile_alu_we                 = 1'b0;
    regfile_alu_waddr_sel_o        = 1'b1;

    prepost_useincr_o              = 1'b1;

    hwlp_we                        = 3'b0;
    hwlp_target_mux_sel_o          = 2'b0;
    hwlp_start_mux_sel_o           = 2'b0;
    hwlp_cnt_mux_sel_o             = 1'b0;

    csr_access_o                   = 1'b0;
    csr_status_o                   = 1'b0;
    csr_illegal                    = 1'b0;
    csr_op                         = CSR_OP_READ;
    mret_insn_o                    = 1'b0;
    uret_insn_o                    = 1'b0;

    dret_insn_o                    = 1'b0;

    data_we_o                      = 1'b0;
    data_type_o                    = 2'b00;
    data_sign_extension_o          = 2'b00;
    data_reg_offset_o              = 2'b00;
    data_req                       = 1'b0;
    data_load_event_o              = 1'b0;

    atop_o                         = 6'b000000;

    illegal_insn_o                 = 1'b0;
    ebrk_insn_o                    = 1'b0;
    ecall_insn_o                   = 1'b0;
    wfi_o                          = 1'b0;

    fencei_insn_o                  = 1'b0;

    rega_used_o                    = 1'b0;
    regb_used_o                    = 1'b0;
    regc_used_o                    = 1'b0;
    reg_fp_a_o                     = 1'b0;
    reg_fp_b_o                     = 1'b0;
    reg_fp_c_o                     = 1'b0;
    reg_fp_d_o                     = 1'b0;

    bmask_a_mux_o                  = BMASK_A_ZERO;
    bmask_b_mux_o                  = BMASK_B_ZERO;
    alu_bmask_a_mux_sel_o          = BMASK_A_IMM;
    alu_bmask_b_mux_sel_o          = BMASK_B_IMM;

    is_clpx_o                      = 1'b0;
    is_subrot_o                    = 1'b0;

    mret_dec_o                     = 1'b0;
    uret_dec_o                     = 1'b0;
    dret_dec_o                     = 1'b0;

    unique case (instr_rdata_i[6:0])

      OPCODE_JAL: begin
        ctrl_transfer_target_mux_sel_o = JT_JAL;
        ctrl_transfer_insn    = BRANCH_JAL;

        alu_op_a_mux_sel_o  = OP_A_CURRPC;
        alu_op_b_mux_sel_o  = OP_B_IMM;
        imm_b_mux_sel_o     = IMMB_PCINCR;
        alu_operator_o      = ALU_ADD;
        regfile_alu_we      = 1'b1;

      end

      OPCODE_JALR: begin
        ctrl_transfer_target_mux_sel_o = JT_JALR;
        ctrl_transfer_insn    = BRANCH_JALR;

        alu_op_a_mux_sel_o  = OP_A_CURRPC;
        alu_op_b_mux_sel_o  = OP_B_IMM;
        imm_b_mux_sel_o     = IMMB_PCINCR;
        alu_operator_o      = ALU_ADD;
        regfile_alu_we      = 1'b1;

        rega_used_o         = 1'b1;

        if (instr_rdata_i[14:12] != 3'b0) begin
          ctrl_transfer_insn = BRANCH_NONE;
          regfile_alu_we     = 1'b0;
          illegal_insn_o     = 1'b1;
        end
      end

      OPCODE_BRANCH: begin
        ctrl_transfer_target_mux_sel_o = JT_COND;
        ctrl_transfer_insn             = BRANCH_COND;
        alu_op_c_mux_sel_o             = OP_C_JT;
        rega_used_o                    = 1'b1;
        regb_used_o                    = 1'b1;

        unique case (instr_rdata_i[14:12])
          3'b000 : alu_operator_o = ALU_EQ;
          3'b001 : alu_operator_o = ALU_NE;
          3'b100 : alu_operator_o = ALU_LTS;
          3'b101 : alu_operator_o = ALU_GES;
          3'b110 : alu_operator_o = ALU_LTU;
          3'b111 : alu_operator_o = ALU_GEU;
          default: illegal_insn_o = 1'b1;
        endcase
      end

      OPCODE_STORE: begin
        data_req           = 1'b1;
        data_we_o          = 1'b1;
        rega_used_o        = 1'b1;
        regb_used_o        = 1'b1;
        alu_operator_o     = ALU_ADD;

        alu_op_c_mux_sel_o = OP_C_REGB_OR_FWD;

        imm_b_mux_sel_o    = IMMB_S;
        alu_op_b_mux_sel_o = OP_B_IMM;

        unique case (instr_rdata_i[14:12])
          3'b000 : data_type_o = 2'b10;
          3'b001 : data_type_o = 2'b01;
          3'b010 : data_type_o = 2'b00;
          default: begin
            illegal_insn_o = 1'b1;
            data_req       = 1'b0;
            data_we_o      = 1'b0;
          end
        endcase
      end

      OPCODE_LOAD: begin
        data_req           = 1'b1;
        regfile_mem_we     = 1'b1;
        rega_used_o        = 1'b1;
        alu_operator_o     = ALU_ADD;

        alu_op_b_mux_sel_o = OP_B_IMM;
        imm_b_mux_sel_o    = IMMB_I;

        data_sign_extension_o = {1'b0,~instr_rdata_i[14]};

        unique case (instr_rdata_i[14:12])
          3'b000, 3'b100: data_type_o = 2'b10;
          3'b001, 3'b101: data_type_o = 2'b01;
          3'b010        : data_type_o = 2'b00;
          default: begin
            illegal_insn_o = 1'b1;
          end
        endcase
      end

      OPCODE_AMO: begin
        if (A_EXTENSION) begin : decode_amo
          if (instr_rdata_i[14:12] == 3'b010) begin
            data_req          = 1'b1;
            data_type_o       = 2'b00;
            rega_used_o       = 1'b1;
            regb_used_o       = 1'b1;
            regfile_mem_we    = 1'b1;
            prepost_useincr_o = 1'b0;
            alu_op_a_mux_sel_o = OP_A_REGA_OR_FWD;

            data_sign_extension_o = 1'b1;

            atop_o = {1'b1, instr_rdata_i[31:27]};

            unique case (instr_rdata_i[31:27])
              AMO_LR: begin
                data_we_o = 1'b0;
              end
              AMO_SC,
              AMO_SWAP,
              AMO_ADD,
              AMO_XOR,
              AMO_AND,
              AMO_OR,
              AMO_MIN,
              AMO_MAX,
              AMO_MINU,
              AMO_MAXU: begin
                data_we_o = 1'b1;
                alu_op_c_mux_sel_o = OP_C_REGB_OR_FWD;
              end
              default : illegal_insn_o = 1'b1;
            endcase
          end
          else begin
            illegal_insn_o = 1'b1;
          end
        end else begin : no_decode_amo
          illegal_insn_o = 1'b1;
        end
      end

      OPCODE_LUI: begin
        alu_op_a_mux_sel_o  = OP_A_IMM;
        alu_op_b_mux_sel_o  = OP_B_IMM;
        imm_a_mux_sel_o     = IMMA_ZERO;
        imm_b_mux_sel_o     = IMMB_U;
        alu_operator_o      = ALU_ADD;
        regfile_alu_we      = 1'b1;
      end

      OPCODE_AUIPC: begin
        alu_op_a_mux_sel_o  = OP_A_CURRPC;
        alu_op_b_mux_sel_o  = OP_B_IMM;
        imm_b_mux_sel_o     = IMMB_U;
        alu_operator_o      = ALU_ADD;
        regfile_alu_we      = 1'b1;
      end

      OPCODE_OPIMM: begin
        alu_op_b_mux_sel_o  = OP_B_IMM;
        imm_b_mux_sel_o     = IMMB_I;
        regfile_alu_we      = 1'b1;
        rega_used_o         = 1'b1;

        unique case (instr_rdata_i[14:12])
          3'b000: alu_operator_o = ALU_ADD;
          3'b010: alu_operator_o = ALU_SLTS;
          3'b011: alu_operator_o = ALU_SLTU;
          3'b100: alu_operator_o = ALU_XOR;
          3'b110: alu_operator_o = ALU_OR;
          3'b111: alu_operator_o = ALU_AND;

          3'b001: begin
            alu_operator_o = ALU_SLL;
            if (instr_rdata_i[31:25] != 7'b0)
              illegal_insn_o = 1'b1;
          end

          3'b101: begin
            if (instr_rdata_i[31:25] == 7'b0)
              alu_operator_o = ALU_SRL;
            else if (instr_rdata_i[31:25] == 7'b010_0000)
              alu_operator_o = ALU_SRA;
            else
              illegal_insn_o = 1'b1;
          end

        endcase
      end

      OPCODE_OP: begin

        if (instr_rdata_i[31:30] == 2'b11) begin
          illegal_insn_o = 1'b1;

        end else if (instr_rdata_i[31:30] == 2'b10) begin
          if (instr_rdata_i[29:25] == 5'b00000) begin
            illegal_insn_o = 1'b1;

          end else begin

            if (FPU == 1 && C_XFVEC == 1) begin

              alu_en           = 1'b0;
              apu_en           = 1'b1;

              rega_used_o      = 1'b1;
              regb_used_o      = 1'b1;
              if (ZFINX == 0) begin
                reg_fp_a_o     = 1'b1;
                reg_fp_b_o     = 1'b1;
                reg_fp_d_o     = 1'b1;
              end else begin
                reg_fp_a_o     = 1'b0;
                reg_fp_b_o     = 1'b0;
                reg_fp_d_o     = 1'b0;
              end
              fpu_vec_op       = 1'b1;

              scalar_replication_o = instr_rdata_i[14];

              check_fprm       = 1'b1;
              fp_rnd_mode_o    = frm_i;

              unique case (instr_rdata_i[13:12])

                2'b00: begin
                  fpu_dst_fmt_o  = cv32e40p_fpu_pkg::FP32;
                  alu_vec_mode_o = VEC_MODE32;
                end

                2'b01: begin
                  fpu_dst_fmt_o  = cv32e40p_fpu_pkg::FP16ALT;
                  alu_vec_mode_o = VEC_MODE16;
                end

                2'b10: begin
                  fpu_dst_fmt_o  = cv32e40p_fpu_pkg::FP16;
                  alu_vec_mode_o = VEC_MODE16;
                end

                2'b11: begin
                  fpu_dst_fmt_o  = cv32e40p_fpu_pkg::FP8;
                  alu_vec_mode_o = VEC_MODE8;
                end
              endcase

              fpu_src_fmt_o = fpu_dst_fmt_o;

              unique case (instr_rdata_i[29:25]) inside

                5'b00001: begin
                  fpu_op      = cv32e40p_fpu_pkg::ADD;
                  fp_op_group = ADDMUL;

                  alu_op_b_mux_sel_o     = OP_B_REGA_OR_FWD;
                  alu_op_c_mux_sel_o     = OP_C_REGB_OR_FWD;
                  scalar_replication_o   = 1'b0;
                  scalar_replication_c_o = instr_rdata_i[14];
                end

                5'b00010: begin
                  fpu_op      = cv32e40p_fpu_pkg::ADD;
                  fpu_op_mod  = 1'b1;
                  fp_op_group = ADDMUL;

                  alu_op_b_mux_sel_o     = OP_B_REGA_OR_FWD;
                  alu_op_c_mux_sel_o     = OP_C_REGB_OR_FWD;
                  scalar_replication_o   = 1'b0;
                  scalar_replication_c_o = instr_rdata_i[14];
                end

                5'b00011: begin
                  fpu_op      = cv32e40p_fpu_pkg::MUL;
                  fp_op_group = ADDMUL;
                end

                5'b00100: begin
                  fpu_op      = cv32e40p_fpu_pkg::DIV;
                  fp_op_group = DIVSQRT;
                end

                5'b00101: begin
                  fpu_op        = cv32e40p_fpu_pkg::MINMAX;
                  fp_rnd_mode_o = 3'b000;
                  fp_op_group   = NONCOMP;
                  check_fprm    = 1'b0;
                end

                5'b00110: begin
                  fpu_op        = cv32e40p_fpu_pkg::MINMAX;
                  fp_rnd_mode_o = 3'b001;
                  fp_op_group   = NONCOMP;
                  check_fprm    = 1'b0;
                end

                5'b00111: begin
                  regb_used_o = 1'b0;
                  fpu_op      = cv32e40p_fpu_pkg::SQRT;
                  fp_op_group = DIVSQRT;

                  if ((instr_rdata_i[24:20] != 5'b00000) || instr_rdata_i[14]) begin
                    illegal_insn_o = 1'b1;
                  end
                end

                5'b01000: begin
                  regc_used_o = 1'b1;
                  regc_mux_o  = REGC_RD;
                  if (ZFINX == 0) begin
                    reg_fp_c_o = 1'b1;
                  end else begin
                    reg_fp_c_o = 1'b0;
                  end
                  fpu_op      = cv32e40p_fpu_pkg::FMADD;
                  fp_op_group = ADDMUL;
                end

                5'b01001: begin
                  regc_used_o = 1'b1;
                  regc_mux_o  = REGC_RD;
                  if (ZFINX == 0) begin
                    reg_fp_c_o = 1'b1;
                  end else begin
                    reg_fp_c_o = 1'b0;
                  end
                  fpu_op      = cv32e40p_fpu_pkg::FMADD;
                  fpu_op_mod  = 1'b1;
                  fp_op_group = ADDMUL;
                end

                5'b01100: begin
                  regb_used_o          = 1'b0;
                  scalar_replication_o = 1'b0;

                  unique case (instr_rdata_i[24:20]) inside

                    5'b00000: begin
                      alu_op_b_mux_sel_o = OP_B_REGA_OR_FWD;
                      fpu_op             = cv32e40p_fpu_pkg::SGNJ;
                      fp_rnd_mode_o      = 3'b011;
                      fp_op_group        = NONCOMP;
                      check_fprm         = 1'b0;

                      if (instr_rdata_i[14]) begin
                        reg_fp_a_o       = 1'b0;
                        fpu_op_mod       = 1'b0;
                      end

                      else begin
                        reg_fp_d_o       = 1'b0;
                        fpu_op_mod       = 1'b1;
                      end
                    end

                    5'b00001: begin
                      reg_fp_d_o    = 1'b0;
                      fpu_op        = cv32e40p_fpu_pkg::CLASSIFY;
                      fp_rnd_mode_o = 3'b000;
                      fp_op_group   = NONCOMP;
                      check_fprm    = 1'b0;

                      if (instr_rdata_i[14]) illegal_insn_o = 1'b1;
                    end

                    5'b0001?: begin
                      fp_op_group = CONV;
                      fpu_op_mod  = instr_rdata_i[14];

                      unique case (instr_rdata_i[13:12])

                        2'b00 : fpu_int_fmt_o = cv32e40p_fpu_pkg::INT32;

                        2'b01,
                        2'b10: fpu_int_fmt_o = cv32e40p_fpu_pkg::INT16;

                        2'b11: fpu_int_fmt_o = cv32e40p_fpu_pkg::INT8;
                      endcase

                      if (instr_rdata_i[20]) begin
                        reg_fp_a_o = 1'b0;
                        fpu_op     = cv32e40p_fpu_pkg::I2F;
                      end

                      else begin
                        reg_fp_d_o = 1'b0;
                        fpu_op     = cv32e40p_fpu_pkg::F2I;
                      end
                    end

                    5'b001??: begin
                      fpu_op      = cv32e40p_fpu_pkg::F2F;
                      fp_op_group = CONV;

                      unique case (instr_rdata_i[21:20])

                        2'b00: begin
                          fpu_src_fmt_o = cv32e40p_fpu_pkg::FP32;
                          if (~C_RVF) illegal_insn_o = 1'b1;
                        end
                        2'b01: begin
                          fpu_src_fmt_o = cv32e40p_fpu_pkg::FP16ALT;
                          if (~C_XF16ALT) illegal_insn_o = 1'b1;
                        end
                        2'b10: begin
                          fpu_src_fmt_o = cv32e40p_fpu_pkg::FP16;
                          if (~C_XF16) illegal_insn_o = 1'b1;
                        end
                        2'b11: begin
                          fpu_src_fmt_o = cv32e40p_fpu_pkg::FP8;
                          if (~C_XF8) illegal_insn_o = 1'b1;
                        end
                      endcase

                      if (instr_rdata_i[14]) illegal_insn_o = 1'b1;
                    end

                    default : illegal_insn_o = 1'b1;
                  endcase
                end

                5'b01101: begin
                  fpu_op        = cv32e40p_fpu_pkg::SGNJ;
                  fp_rnd_mode_o = 3'b000;
                  fp_op_group   = NONCOMP;
                  check_fprm    = 1'b0;
                end

                5'b01110: begin
                  fpu_op        = cv32e40p_fpu_pkg::SGNJ;
                  fp_rnd_mode_o = 3'b001;
                  fp_op_group   = NONCOMP;
                  check_fprm    = 1'b0;
                end

                5'b01111: begin
                  fpu_op        = cv32e40p_fpu_pkg::SGNJ;
                  fp_rnd_mode_o = 3'b010;
                  fp_op_group   = NONCOMP;
                  check_fprm    = 1'b0;
                end

                5'b10000: begin
                  reg_fp_d_o    = 1'b0;
                  fpu_op        = cv32e40p_fpu_pkg::CMP;
                  fp_rnd_mode_o = 3'b010;
                  fp_op_group   = NONCOMP;
                  check_fprm    = 1'b0;
                end

                5'b10001: begin
                  reg_fp_d_o    = 1'b0;
                  fpu_op        = cv32e40p_fpu_pkg::CMP;
                  fpu_op_mod    = 1'b1;
                  fp_rnd_mode_o = 3'b010;
                  fp_op_group   = NONCOMP;
                  check_fprm    = 1'b0;
                end

                5'b10010: begin
                  reg_fp_d_o    = 1'b0;
                  fpu_op        = cv32e40p_fpu_pkg::CMP;
                  fp_rnd_mode_o = 3'b001;
                  fp_op_group   = NONCOMP;
                  check_fprm    = 1'b0;
                end

                5'b10011: begin
                  reg_fp_d_o    = 1'b0;
                  fpu_op        = cv32e40p_fpu_pkg::CMP;
                  fpu_op_mod    = 1'b1;
                  fp_rnd_mode_o = 3'b001;
                  fp_op_group   = NONCOMP;
                  check_fprm    = 1'b0;
                end

                5'b10100: begin
                  reg_fp_d_o    = 1'b0;
                  fpu_op        = cv32e40p_fpu_pkg::CMP;
                  fp_rnd_mode_o = 3'b000;
                  fp_op_group   = NONCOMP;
                  check_fprm    = 1'b0;
                end

                5'b10101: begin
                  reg_fp_d_o    = 1'b0;
                  fpu_op        = cv32e40p_fpu_pkg::CMP;
                  fpu_op_mod    = 1'b1;
                  fp_rnd_mode_o = 3'b000;
                  fp_op_group   = NONCOMP;
                  check_fprm    = 1'b0;
                end

                5'b110??: begin

                  fpu_op_mod           = instr_rdata_i[14];
                  fp_op_group          = CONV;
                  scalar_replication_o = 1'b0;

                  if (instr_rdata_i[25]) fpu_op = cv32e40p_fpu_pkg::CPKCD;
                  else fpu_op = cv32e40p_fpu_pkg::CPKAB;

                  if (instr_rdata_i[26]) begin
                    fpu_src_fmt_o  = cv32e40p_fpu_pkg::FP64;
                    if (~C_RVD) illegal_insn_o = 1'b1;
                  end

                  else begin
                    fpu_src_fmt_o  = cv32e40p_fpu_pkg::FP32;
                    if (~C_RVF) illegal_insn_o = 1'b1;
                  end

                  if (fpu_op == cv32e40p_fpu_pkg::CPKCD) begin
                    if (~C_XF8 || ~C_RVD) illegal_insn_o = 1'b1;
                  end else begin
                    if (instr_rdata_i[14]) begin

                      if (fpu_dst_fmt_o == cv32e40p_fpu_pkg::FP32) illegal_insn_o = 1'b1;

                      if (~C_RVD && (fpu_dst_fmt_o != cv32e40p_fpu_pkg::FP8)) illegal_insn_o = 1'b1;
                    end
                  end
                end

                default: begin
                  illegal_insn_o = 1'b1;
                end
              endcase

              if ((~C_RVF || ~C_RVD) && fpu_dst_fmt_o == cv32e40p_fpu_pkg::FP32) illegal_insn_o = 1'b1;

              if ((~C_XF16 || ~C_RVF) && fpu_dst_fmt_o == cv32e40p_fpu_pkg::FP16) illegal_insn_o = 1'b1;

              if ((~C_XF16ALT || ~C_RVF) && fpu_dst_fmt_o == cv32e40p_fpu_pkg::FP16ALT) begin
                illegal_insn_o = 1'b1;
              end

              if ((~C_XF8 || (~C_XF16 && ~C_XF16ALT)) && fpu_dst_fmt_o == cv32e40p_fpu_pkg::FP8) begin
                illegal_insn_o = 1'b1;
              end

              if (check_fprm) begin
                unique case (frm_i) inside
                  [3'b000:3'b100] : ;
                  default         : illegal_insn_o = 1'b1;
                endcase
              end

              case (fp_op_group)

                ADDMUL : begin
                  unique case (fpu_dst_fmt_o)
                    cv32e40p_fpu_pkg::FP32    : apu_lat_o = (FPU_ADDMUL_LAT<2)? FPU_ADDMUL_LAT+1: 2'h3;
                    cv32e40p_fpu_pkg::FP16    : apu_lat_o = (C_LAT_FP16<2)    ? C_LAT_FP16+1    : 2'h3;
                    cv32e40p_fpu_pkg::FP16ALT : apu_lat_o = (C_LAT_FP16ALT<2) ? C_LAT_FP16ALT+1 : 2'h3;
                    cv32e40p_fpu_pkg::FP8     : apu_lat_o = (C_LAT_FP8<2)     ? C_LAT_FP8+1     : 2'h3;
                    default : ;
                  endcase
                end

                DIVSQRT : apu_lat_o = 2'h3;

                NONCOMP : apu_lat_o = (FPU_OTHERS_LAT<2) ? FPU_OTHERS_LAT+1 : 2'h3;

                CONV    : apu_lat_o = (FPU_OTHERS_LAT<2) ? FPU_OTHERS_LAT+1 : 2'h3;
              endcase

              apu_op_o = {fpu_vec_op, fpu_op_mod, fpu_op};

            end else begin
              illegal_insn_o = 1'b1;
            end
          end

        end

        else begin
          regfile_alu_we = 1'b1;
          rega_used_o    = 1'b1;

          if (~instr_rdata_i[28]) regb_used_o = 1'b1;

          unique case ({instr_rdata_i[30:25], instr_rdata_i[14:12]})

            {6'b00_0000, 3'b000}: alu_operator_o = ALU_ADD;
            {6'b10_0000, 3'b000}: alu_operator_o = ALU_SUB;
            {6'b00_0000, 3'b010}: alu_operator_o = ALU_SLTS;
            {6'b00_0000, 3'b011}: alu_operator_o = ALU_SLTU;
            {6'b00_0000, 3'b100}: alu_operator_o = ALU_XOR;
            {6'b00_0000, 3'b110}: alu_operator_o = ALU_OR;
            {6'b00_0000, 3'b111}: alu_operator_o = ALU_AND;
            {6'b00_0000, 3'b001}: alu_operator_o = ALU_SLL;
            {6'b00_0000, 3'b101}: alu_operator_o = ALU_SRL;
            {6'b10_0000, 3'b101}: alu_operator_o = ALU_SRA;

            {6'b00_0001, 3'b000}: begin
              alu_en          = 1'b0;
              mult_int_en     = 1'b1;
              mult_operator_o = MUL_MAC32;
              regc_mux_o      = REGC_ZERO;
            end
            {6'b00_0001, 3'b001}: begin
              alu_en             = 1'b0;
              mult_int_en        = 1'b1;
              regc_used_o        = 1'b1;
              regc_mux_o         = REGC_ZERO;
              mult_signed_mode_o = 2'b11;
              mult_operator_o    = MUL_H;
            end
            {6'b00_0001, 3'b010}: begin
              alu_en             = 1'b0;
              mult_int_en        = 1'b1;
              regc_used_o        = 1'b1;
              regc_mux_o         = REGC_ZERO;
              mult_signed_mode_o = 2'b01;
              mult_operator_o    = MUL_H;
            end
            {6'b00_0001, 3'b011}: begin
              alu_en             = 1'b0;
              mult_int_en        = 1'b1;
              regc_used_o        = 1'b1;
              regc_mux_o         = REGC_ZERO;
              mult_signed_mode_o = 2'b00;
              mult_operator_o    = MUL_H;
            end
            {6'b00_0001, 3'b100}: begin
              alu_op_a_mux_sel_o = OP_A_REGB_OR_FWD;
              alu_op_b_mux_sel_o = OP_B_REGA_OR_FWD;
              regb_used_o        = 1'b1;
              alu_operator_o     = ALU_DIV;
            end
            {6'b00_0001, 3'b101}: begin
              alu_op_a_mux_sel_o = OP_A_REGB_OR_FWD;
              alu_op_b_mux_sel_o = OP_B_REGA_OR_FWD;
              regb_used_o        = 1'b1;
              alu_operator_o     = ALU_DIVU;
            end
            {6'b00_0001, 3'b110}: begin
              alu_op_a_mux_sel_o = OP_A_REGB_OR_FWD;
              alu_op_b_mux_sel_o = OP_B_REGA_OR_FWD;
              regb_used_o        = 1'b1;
              alu_operator_o     = ALU_REM;
            end
            {6'b00_0001, 3'b111}: begin
              alu_op_a_mux_sel_o = OP_A_REGB_OR_FWD;
              alu_op_b_mux_sel_o = OP_B_REGA_OR_FWD;
              regb_used_o        = 1'b1;
              alu_operator_o     = ALU_REMU;
            end

            default: begin
              illegal_insn_o = 1'b1;
            end
          endcase
        end
      end

      OPCODE_OP_FP: begin
        if (FPU == 1 && (ZFINX == 1 || fs_off_i == 1'b0)) begin

          alu_en           = 1'b0;
          apu_en           = 1'b1;

          rega_used_o      = 1'b1;
          regb_used_o      = 1'b1;
          if (ZFINX == 0) begin
            reg_fp_a_o     = 1'b1;
            reg_fp_b_o     = 1'b1;
            reg_fp_d_o     = 1'b1;
          end else begin
            reg_fp_a_o     = 1'b0;
            reg_fp_b_o     = 1'b0;
            reg_fp_d_o     = 1'b0;
          end

          check_fprm       = 1'b1;
          fp_rnd_mode_o    = instr_rdata_i[14:12];

          unique case (instr_rdata_i[26:25])

            2'b00: fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP32;

            2'b01: fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP64;

            2'b10: begin

              if (instr_rdata_i[14:12] == 3'b101) fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP16ALT;

              else fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP16;
            end

            2'b11: fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP8;
          endcase

          fpu_src_fmt_o = fpu_dst_fmt_o;

          unique case (instr_rdata_i[31:27])

            5'b00000: begin
              fpu_op             = cv32e40p_fpu_pkg::ADD;
              fp_op_group        = ADDMUL;
              alu_op_b_mux_sel_o = OP_B_REGA_OR_FWD;
              alu_op_c_mux_sel_o = OP_C_REGB_OR_FWD;
            end

            5'b00001: begin
              fpu_op             = cv32e40p_fpu_pkg::ADD;
              fpu_op_mod         = 1'b1;
              fp_op_group        = ADDMUL;
              alu_op_b_mux_sel_o = OP_B_REGA_OR_FWD;
              alu_op_c_mux_sel_o = OP_C_REGB_OR_FWD;
            end

            5'b00010: begin
              fpu_op      = cv32e40p_fpu_pkg::MUL;
              fp_op_group = ADDMUL;
            end

            5'b00011: begin
              fpu_op      = cv32e40p_fpu_pkg::DIV;
              fp_op_group = DIVSQRT;
            end

            5'b01011: begin
              regb_used_o = 1'b0;
              fpu_op      = cv32e40p_fpu_pkg::SQRT;
              fp_op_group = DIVSQRT;

              if (instr_rdata_i[24:20] != 5'b00000) illegal_insn_o = 1'b1;
            end

            5'b00100: begin
              fpu_op        = cv32e40p_fpu_pkg::SGNJ;
              fp_op_group   = NONCOMP;
              check_fprm    = 1'b0;
              if (C_XF16ALT) begin
                if (!(instr_rdata_i[14:12] inside {[3'b000:3'b010], [3'b100:3'b110]})) begin
                  illegal_insn_o = 1'b1;
                end

                if (instr_rdata_i[14]) begin
                  fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP16ALT;
                  fpu_src_fmt_o = cv32e40p_fpu_pkg::FP16ALT;
                end else begin
                  fp_rnd_mode_o = {1'b0, instr_rdata_i[13:12]};
                end
              end else begin
                if (!(instr_rdata_i[14:12] inside {[3'b000:3'b010]})) illegal_insn_o = 1'b1;
              end
            end

            5'b00101: begin
              fpu_op        = cv32e40p_fpu_pkg::MINMAX;
              fp_op_group   = NONCOMP;
              check_fprm    = 1'b0;
              if (C_XF16ALT) begin
                if (!(instr_rdata_i[14:12] inside {[3'b000:3'b001], [3'b100:3'b101]})) begin
                  illegal_insn_o = 1'b1;
                end

                if (instr_rdata_i[14]) begin
                  fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP16ALT;
                  fpu_src_fmt_o = cv32e40p_fpu_pkg::FP16ALT;
                end else begin
                  fp_rnd_mode_o = {1'b0, instr_rdata_i[13:12]};
                end
              end else begin
                if (!(instr_rdata_i[14:12] inside {[3'b000:3'b001]})) illegal_insn_o = 1'b1;
              end
            end

            5'b01000: begin
              regb_used_o   = 1'b0;
              fpu_op        = cv32e40p_fpu_pkg::F2F;
              fp_op_group   = CONV;

              if (instr_rdata_i[24:23]) illegal_insn_o = 1'b1;

              unique case (instr_rdata_i[22:20])

                3'b000: begin
                  if (!(C_RVF && (C_XF16 || C_XF16ALT || C_XF8))) illegal_insn_o = 1'b1;
                  fpu_src_fmt_o = cv32e40p_fpu_pkg::FP32;
                end
                3'b001: begin
                  if (~C_RVD) illegal_insn_o = 1'b1;
                  fpu_src_fmt_o = cv32e40p_fpu_pkg::FP64;
                end
                3'b010: begin
                  if (~C_XF16) illegal_insn_o = 1'b1;
                  fpu_src_fmt_o = cv32e40p_fpu_pkg::FP16;
                end
                3'b110: begin
                  if (~C_XF16ALT) illegal_insn_o = 1'b1;
                  fpu_src_fmt_o = cv32e40p_fpu_pkg::FP16ALT;
                end
                3'b011: begin
                  if (~C_XF8) illegal_insn_o = 1'b1;
                  fpu_src_fmt_o = cv32e40p_fpu_pkg::FP8;
                end
                default: illegal_insn_o = 1'b1;
              endcase
            end

            5'b01001: begin
              if (~C_XF16 && ~C_XF16ALT && ~C_XF8) illegal_insn_o = 1;
              fpu_op        = cv32e40p_fpu_pkg::MUL;
              fp_op_group   = ADDMUL;

              fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP32;
            end

            5'b01010: begin
              if (~C_XF16 && ~C_XF16ALT && ~C_XF8) illegal_insn_o = 1;
              regc_used_o = 1'b1;
              regc_mux_o  = REGC_RD;
              if (ZFINX == 0) begin
                reg_fp_c_o = 1'b1;
              end else begin
                reg_fp_c_o = 1'b0;
              end
              fpu_op      = cv32e40p_fpu_pkg::FMADD;
              fp_op_group = ADDMUL;

              fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP32;
            end

            5'b10100: begin
              fpu_op        = cv32e40p_fpu_pkg::CMP;
              fp_op_group   = NONCOMP;
              reg_fp_d_o    = 1'b0;
              check_fprm    = 1'b0;
              if (C_XF16ALT) begin
                if (!(instr_rdata_i[14:12] inside {[3'b000:3'b010], [3'b100:3'b110]})) begin
                  illegal_insn_o = 1'b1;
                end

                if (instr_rdata_i[14]) begin
                  fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP16ALT;
                  fpu_src_fmt_o = cv32e40p_fpu_pkg::FP16ALT;
                end else begin
                  fp_rnd_mode_o = {1'b0, instr_rdata_i[13:12]};
                end
              end else begin
                if (!(instr_rdata_i[14:12] inside {[3'b000:3'b010]})) illegal_insn_o = 1'b1;
              end
            end

            5'b11000: begin
              regb_used_o = 1'b0;
              reg_fp_d_o  = 1'b0;
              fpu_op      = cv32e40p_fpu_pkg::F2I;
              fp_op_group = CONV;
              fpu_op_mod  = instr_rdata_i[20];

              unique case (instr_rdata_i[26:25])
                2'b00: begin
                  if (~C_RVF) illegal_insn_o = 1;
                  else fpu_src_fmt_o = cv32e40p_fpu_pkg::FP32;
                end
                2'b01: begin
                  if (~C_RVD) illegal_insn_o = 1;
                  else fpu_src_fmt_o = cv32e40p_fpu_pkg::FP64;
                end
                2'b10: begin
                  if (instr_rdata_i[14:12] == 3'b101) begin
                    if (~C_XF16ALT) illegal_insn_o = 1;
                    else fpu_src_fmt_o = cv32e40p_fpu_pkg::FP16ALT;
                  end else if (~C_XF16) begin
                    illegal_insn_o = 1;
                  end else begin
                    fpu_src_fmt_o = cv32e40p_fpu_pkg::FP16;
                  end
                end
                2'b11: begin
                  if (~C_XF8) illegal_insn_o = 1;
                  else fpu_src_fmt_o = cv32e40p_fpu_pkg::FP8;
                end
              endcase

              if (instr_rdata_i[24:21]) illegal_insn_o = 1'b1;
            end

            5'b11010: begin
              regb_used_o = 1'b0;
              reg_fp_a_o  = 1'b0;
              fpu_op      = cv32e40p_fpu_pkg::I2F;
              fp_op_group = CONV;
              fpu_op_mod  = instr_rdata_i[20];

              if (instr_rdata_i[24:21]) illegal_insn_o = 1'b1;
            end

            5'b11100: begin
              regb_used_o = 1'b0;
              reg_fp_d_o  = 1'b0;
              fp_op_group = NONCOMP;
              check_fprm  = 1'b0;

              if ((ZFINX == 0 && instr_rdata_i[14:12] == 3'b000) || (C_XF16ALT && instr_rdata_i[14:12] == 3'b100)) begin
                alu_op_b_mux_sel_o  = OP_B_REGA_OR_FWD;
                fpu_op              = cv32e40p_fpu_pkg::SGNJ;
                fpu_op_mod          = 1'b1;
                fp_rnd_mode_o       = 3'b011;

                if (instr_rdata_i[14]) begin
                  fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP16ALT;
                  fpu_src_fmt_o = cv32e40p_fpu_pkg::FP16ALT;
                end

              end else if (instr_rdata_i[14:12] == 3'b001 || (C_XF16ALT && instr_rdata_i[14:12] == 3'b101)) begin
                fpu_op        = cv32e40p_fpu_pkg::CLASSIFY;
                fp_rnd_mode_o = 3'b000;

                if (instr_rdata_i[14]) begin
                  fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP16ALT;
                  fpu_src_fmt_o = cv32e40p_fpu_pkg::FP16ALT;
                end
              end else begin
                illegal_insn_o = 1'b1;
              end

              if (instr_rdata_i[24:20]) illegal_insn_o = 1'b1;
            end

            5'b11110: begin
              regb_used_o         = 1'b0;
              reg_fp_a_o          = 1'b0;
              alu_op_b_mux_sel_o  = OP_B_REGA_OR_FWD;
              fpu_op              = cv32e40p_fpu_pkg::SGNJ;
              fpu_op_mod          = 1'b0;
              fp_op_group         = NONCOMP;
              fp_rnd_mode_o       = 3'b011;
              check_fprm          = 1'b0;
              if ((ZFINX == 0 && instr_rdata_i[14:12] == 3'b000) || (C_XF16ALT && instr_rdata_i[14:12] == 3'b100)) begin

                if (instr_rdata_i[14]) begin
                  fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP16ALT;
                  fpu_src_fmt_o = cv32e40p_fpu_pkg::FP16ALT;
                end
              end else begin
                illegal_insn_o = 1'b1;
              end

              if (instr_rdata_i[24:20] != 5'b00000) illegal_insn_o = 1'b1;
            end

            default: illegal_insn_o = 1'b1;
          endcase

          if (~C_RVF && fpu_dst_fmt_o == cv32e40p_fpu_pkg::FP32) illegal_insn_o = 1'b1;
          if ((~C_RVD) && fpu_dst_fmt_o == cv32e40p_fpu_pkg::FP64) illegal_insn_o = 1'b1;
          if ((~C_XF16) && fpu_dst_fmt_o == cv32e40p_fpu_pkg::FP16) illegal_insn_o = 1'b1;
          if ((~C_XF16ALT) && fpu_dst_fmt_o == cv32e40p_fpu_pkg::FP16ALT) begin
            illegal_insn_o = 1'b1;
          end
          if ((~C_XF8) && fpu_dst_fmt_o == cv32e40p_fpu_pkg::FP8) illegal_insn_o = 1'b1;

          if (check_fprm) begin
            unique case (instr_rdata_i[14:12]) inside
              3'b000, 3'b001, 3'b010, 3'b011, 3'b100: ;
              3'b101: begin
                if (~C_XF16ALT || fpu_dst_fmt_o != cv32e40p_fpu_pkg::FP16ALT) illegal_insn_o = 1'b1;

                unique case (frm_i) inside
                  3'b000, 3'b001, 3'b010, 3'b011, 3'b100 : fp_rnd_mode_o = frm_i;
                  default                                : illegal_insn_o = 1'b1;
                endcase
              end
              3'b111: begin

                unique case (frm_i) inside
                  3'b000, 3'b001, 3'b010, 3'b011, 3'b100 : fp_rnd_mode_o = frm_i;
                  default                                : illegal_insn_o = 1'b1;
                endcase
              end
              default : illegal_insn_o = 1'b1;
            endcase
          end

          case (fp_op_group)

            ADDMUL : begin
              unique case (fpu_dst_fmt_o)
                cv32e40p_fpu_pkg::FP32    : apu_lat_o = (FPU_ADDMUL_LAT<2)? FPU_ADDMUL_LAT+1: 2'h3;
                cv32e40p_fpu_pkg::FP64    : apu_lat_o = (C_LAT_FP64<2)    ? C_LAT_FP64+1    : 2'h3;
                cv32e40p_fpu_pkg::FP16    : apu_lat_o = (C_LAT_FP16<2)    ? C_LAT_FP16+1    : 2'h3;
                cv32e40p_fpu_pkg::FP16ALT : apu_lat_o = (C_LAT_FP16ALT<2) ? C_LAT_FP16ALT+1 : 2'h3;
                cv32e40p_fpu_pkg::FP8     : apu_lat_o = (C_LAT_FP8<2)     ? C_LAT_FP8+1     : 2'h3;
                default : ;
              endcase
            end

            DIVSQRT : apu_lat_o = 2'h3;

            NONCOMP : apu_lat_o = (FPU_OTHERS_LAT<2) ? FPU_OTHERS_LAT+1 : 2'h3;

            CONV    : apu_lat_o = (FPU_OTHERS_LAT<2) ? FPU_OTHERS_LAT+1 : 2'h3;
            default: ;
          endcase

          apu_op_o = {fpu_vec_op, fpu_op_mod, fpu_op};

        end else begin
          illegal_insn_o = 1'b1;
        end
      end

      OPCODE_OP_FMADD,
      OPCODE_OP_FMSUB,
      OPCODE_OP_FNMSUB,
      OPCODE_OP_FNMADD : begin
        if (FPU == 1 && (ZFINX == 1 || fs_off_i == 1'b0)) begin

          alu_en        = 1'b0;
          apu_en        = 1'b1;

          rega_used_o   = 1'b1;
          regb_used_o   = 1'b1;
          regc_used_o   = 1'b1;
          regc_mux_o    = REGC_S4;
          if (ZFINX == 0) begin
            reg_fp_a_o  = 1'b1;
            reg_fp_b_o  = 1'b1;
            reg_fp_c_o  = 1'b1;
            reg_fp_d_o  = 1'b1;
          end else begin
            reg_fp_a_o  = 1'b0;
            reg_fp_b_o  = 1'b0;
            reg_fp_c_o  = 1'b0;
            reg_fp_d_o  = 1'b0;
          end
          fp_rnd_mode_o = instr_rdata_i[14:12];

          unique case (instr_rdata_i[26:25])

            2'b00 : fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP32;

            2'b01 : fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP64;

            2'b10 : begin

              if (instr_rdata_i[14:12] == 3'b101) fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP16ALT;
              else fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP16;
            end

            2'b11 : fpu_dst_fmt_o = cv32e40p_fpu_pkg::FP8;
          endcase

          fpu_src_fmt_o = fpu_dst_fmt_o;

          unique case (instr_rdata_i[6:0])

            OPCODE_OP_FMADD : begin
              fpu_op     = cv32e40p_fpu_pkg::FMADD;
            end

            OPCODE_OP_FMSUB : begin
              fpu_op     = cv32e40p_fpu_pkg::FMADD;
              fpu_op_mod = 1'b1;
            end

            OPCODE_OP_FNMSUB : begin
              fpu_op     = cv32e40p_fpu_pkg::FNMSUB;
            end

            OPCODE_OP_FNMADD : begin
              fpu_op     = cv32e40p_fpu_pkg::FNMSUB;
              fpu_op_mod = 1'b1;
            end
            default : ;
          endcase

          if (~C_RVF && fpu_dst_fmt_o == cv32e40p_fpu_pkg::FP32) illegal_insn_o = 1'b1;
          if ((~C_RVD) && fpu_dst_fmt_o == cv32e40p_fpu_pkg::FP64) illegal_insn_o = 1'b1;
          if ((~C_XF16) && fpu_dst_fmt_o == cv32e40p_fpu_pkg::FP16) illegal_insn_o = 1'b1;
          if ((~C_XF16ALT) && fpu_dst_fmt_o == cv32e40p_fpu_pkg::FP16ALT) begin
            illegal_insn_o = 1'b1;
          end
          if ((~C_XF8) && fpu_dst_fmt_o == cv32e40p_fpu_pkg::FP8) illegal_insn_o = 1'b1;

          unique case (instr_rdata_i[14:12]) inside
            3'b000, 3'b001, 3'b010, 3'b011, 3'b100: ;
            3'b101: begin
              if (~C_XF16ALT || fpu_dst_fmt_o != cv32e40p_fpu_pkg::FP16ALT) illegal_insn_o = 1'b1;

              unique case (frm_i) inside
                3'b000, 3'b001, 3'b010, 3'b011, 3'b100 : fp_rnd_mode_o = frm_i;
                default         : illegal_insn_o = 1'b1;
              endcase
            end
            3'b111: begin

              unique case (frm_i) inside
                3'b000, 3'b001, 3'b010, 3'b011, 3'b100 : fp_rnd_mode_o = frm_i;
                default         : illegal_insn_o = 1'b1;
              endcase
            end
            default : illegal_insn_o = 1'b1;
          endcase

          unique case (fpu_dst_fmt_o)
            cv32e40p_fpu_pkg::FP32    : apu_lat_o = (FPU_ADDMUL_LAT<2)? FPU_ADDMUL_LAT+1: 2'h3;
            cv32e40p_fpu_pkg::FP64    : apu_lat_o = (C_LAT_FP64<2)    ? C_LAT_FP64+1    : 2'h3;
            cv32e40p_fpu_pkg::FP16    : apu_lat_o = (C_LAT_FP16<2)    ? C_LAT_FP16+1    : 2'h3;
            cv32e40p_fpu_pkg::FP16ALT : apu_lat_o = (C_LAT_FP16ALT<2) ? C_LAT_FP16ALT+1 : 2'h3;
            cv32e40p_fpu_pkg::FP8     : apu_lat_o = (C_LAT_FP8<2)     ? C_LAT_FP8+1     : 2'h3;
            default : ;
          endcase

          apu_op_o = {fpu_vec_op, fpu_op_mod, fpu_op};

        end else begin
          illegal_insn_o = 1'b1;
        end
      end

      OPCODE_STORE_FP: begin
        if (FPU == 1 && ZFINX == 0 && fs_off_i == 1'b0) begin
          data_req            = 1'b1;
          data_we_o           = 1'b1;
          rega_used_o         = 1'b1;
          regb_used_o         = 1'b1;
          alu_operator_o      = ALU_ADD;
          reg_fp_b_o          = 1'b1;

          imm_b_mux_sel_o     = IMMB_S;
          alu_op_b_mux_sel_o  = OP_B_IMM;

          alu_op_c_mux_sel_o = OP_C_REGB_OR_FWD;

          unique case (instr_rdata_i[14:12])

            3'b000 : if (C_XF8) data_type_o = 2'b10;
                     else illegal_insn_o = 1'b1;

            3'b001 : if (C_XF16 | C_XF16ALT) data_type_o = 2'b01;
                     else illegal_insn_o = 1'b1;

            3'b010 : if (C_RVF) data_type_o = 2'b00;
                     else illegal_insn_o = 1'b1;

            3'b011 : if (C_RVD) data_type_o = 2'b00;
                     else illegal_insn_o = 1'b1;
            default: illegal_insn_o = 1'b1;
          endcase

          if (illegal_insn_o) begin
            data_req       = 1'b0;
            data_we_o      = 1'b0;
          end

        end else begin
          illegal_insn_o = 1'b1;
        end
      end

      OPCODE_LOAD_FP: begin
        if (FPU == 1 && ZFINX == 0 && fs_off_i == 1'b0) begin
          data_req            = 1'b1;
          regfile_mem_we      = 1'b1;
          reg_fp_d_o          = 1'b1;
          rega_used_o         = 1'b1;
          alu_operator_o      = ALU_ADD;

          imm_b_mux_sel_o     = IMMB_I;
          alu_op_b_mux_sel_o  = OP_B_IMM;

          data_sign_extension_o = 2'b10;

          unique case (instr_rdata_i[14:12])

            3'b000 : if (C_XF8) data_type_o = 2'b10;
                     else illegal_insn_o = 1'b1;

            3'b001 : if (C_XF16 | C_XF16ALT) data_type_o = 2'b01;
                     else illegal_insn_o = 1'b1;

            3'b010 : if (C_RVF) data_type_o = 2'b00;
                     else illegal_insn_o = 1'b1;

            3'b011 : if (C_RVD) data_type_o = 2'b00;
                     else illegal_insn_o = 1'b1;
            default: illegal_insn_o = 1'b1;
          endcase

        end else begin
          illegal_insn_o = 1'b1;
        end
      end

      OPCODE_CUSTOM_0: begin
        if (COREV_PULP && instr_rdata_i[14:13] != 2'b11) begin
          data_req           = 1'b1;
          regfile_mem_we     = 1'b1;
          rega_used_o        = 1'b1;
          alu_operator_o     = ALU_ADD;

          alu_op_b_mux_sel_o = OP_B_IMM;
          imm_b_mux_sel_o    = IMMB_I;

          if (instr_rdata_i[13:12] != 2'b11) begin
            prepost_useincr_o       = 1'b0;
            regfile_alu_waddr_sel_o = 1'b0;
            regfile_alu_we          = 1'b1;
          end

          data_sign_extension_o = {1'b0,~instr_rdata_i[14]};

          unique case (instr_rdata_i[13:12])
            2'b00  : data_type_o = 2'b10;
            2'b01  : data_type_o = 2'b01;
            default: data_type_o = 2'b00;
          endcase

          if (instr_rdata_i[13:12] == 2'b11) begin
            if (COREV_CLUSTER) begin
              data_load_event_o = 1'b1;
            end else begin

              illegal_insn_o    = 1'b1;
            end
          end
        end else if (COREV_PULP) begin
          ctrl_transfer_target_mux_sel_o = JT_COND;
          ctrl_transfer_insn             = BRANCH_COND;
          alu_op_c_mux_sel_o             = OP_C_JT;
          rega_used_o                    = 1'b1;

          alu_op_b_mux_sel_o             = OP_B_IMM;
          imm_b_mux_sel_o                = IMMB_BI;

          if (instr_rdata_i[12] == 1'b0) begin
            alu_operator_o      = ALU_EQ;
          end else begin
            alu_operator_o      = ALU_NE;
          end
        end else begin
          illegal_insn_o = 1'b1;
        end
      end

      OPCODE_CUSTOM_1: begin
        if (COREV_PULP) begin
          unique case (instr_rdata_i[14:12])
            3'b000, 3'b001, 3'b010: begin
              data_req                = 1'b1;
              data_we_o               = 1'b1;
              rega_used_o             = 1'b1;
              regb_used_o             = 1'b1;
              alu_operator_o          = ALU_ADD;

              alu_op_c_mux_sel_o      = OP_C_REGB_OR_FWD;

              imm_b_mux_sel_o         = IMMB_S;
              alu_op_b_mux_sel_o      = OP_B_IMM;

              prepost_useincr_o       = 1'b0;
              regfile_alu_waddr_sel_o = 1'b0;
              regfile_alu_we          = 1'b1;

              unique case (instr_rdata_i[13:12])
                2'b00  : data_type_o = 2'b10;
                2'b01  : data_type_o = 2'b01;
                default: data_type_o = 2'b00;
              endcase
            end

            3'b011 : begin
              unique case (instr_rdata_i[31:25])
                7'b0000000, 7'b0000001, 7'b0000010, 7'b0000011,
                7'b0000100, 7'b0000101, 7'b0000110, 7'b0000111,
                7'b0001000, 7'b0001001, 7'b0001010, 7'b0001011,
                7'b0001100, 7'b0001101, 7'b0001110, 7'b0001111: begin
                  data_req           = 1'b1;
                  regfile_mem_we     = 1'b1;
                  rega_used_o        = 1'b1;
                  alu_operator_o     = ALU_ADD;

                  regb_used_o        = 1'b1;
                  alu_op_b_mux_sel_o = OP_B_REGB_OR_FWD;

                  if (instr_rdata_i[27] == 1'b0) begin
                    prepost_useincr_o       = 1'b0;
                    regfile_alu_waddr_sel_o = 1'b0;
                    regfile_alu_we          = 1'b1;
                  end

                  data_sign_extension_o = {1'b0,~instr_rdata_i[28]};

                  unique case ({instr_rdata_i[28],instr_rdata_i[26:25]})
                    3'b000 : data_type_o = 2'b10;
                    3'b001 : data_type_o = 2'b01;
                    3'b010 : data_type_o = 2'b00;
                    3'b100 : data_type_o = 2'b10;
                    3'b101 : data_type_o = 2'b01;
                    default: begin
                      illegal_insn_o = 1'b1;
                      data_req       = 1'b0;
                      regfile_mem_we = 1'b0;
                      regfile_alu_we = 1'b0;
                    end
                  endcase
                end

                7'b0010000, 7'b0010001, 7'b0010010, 7'b0010011,
                7'b0010100, 7'b0010101, 7'b0010110, 7'b0010111: begin
                  data_req           = 1'b1;
                  data_we_o          = 1'b1;
                  rega_used_o        = 1'b1;
                  regb_used_o        = 1'b1;
                  alu_operator_o     = ALU_ADD;

                  alu_op_c_mux_sel_o = OP_C_REGB_OR_FWD;

                  regc_used_o        = 1'b1;
                  alu_op_b_mux_sel_o = OP_B_REGC_OR_FWD;
                  regc_mux_o         = REGC_RD;

                  if (instr_rdata_i[27] == 1'b0) begin
                    prepost_useincr_o       = 1'b0;
                    regfile_alu_waddr_sel_o = 1'b0;
                    regfile_alu_we          = 1'b1;
                  end

                  unique case (instr_rdata_i[26:25])
                    2'b00  : data_type_o = 2'b10;
                    2'b01  : data_type_o = 2'b01;
                    2'b10  : data_type_o = 2'b00;
                    default: begin
                      illegal_insn_o = 1'b1;
                      data_req       = 1'b0;
                      data_we_o      = 1'b0;
                      data_type_o    = 2'b00;
                    end
                  endcase
                end

                7'b0011000, 7'b0011001, 7'b0011010, 7'b0011011,
                7'b0011100, 7'b0011101, 7'b0011110, 7'b0011111: begin
                  regfile_alu_we        = 1'b1;
                  rega_used_o           = 1'b1;
                  regb_used_o           = 1'b1;

                  bmask_a_mux_o         = BMASK_A_S3;
                  bmask_b_mux_o         = BMASK_B_S2;
                  alu_op_b_mux_sel_o    = OP_B_IMM;
                  alu_bmask_a_mux_sel_o = BMASK_A_REG;

                  unique case (instr_rdata_i[27:25])
                    3'b000: begin
                      alu_operator_o        = ALU_BEXT;
                      imm_b_mux_sel_o       = IMMB_S2;
                      bmask_b_mux_o         = BMASK_B_ZERO;
                      alu_op_b_mux_sel_o    = OP_B_BMASK;
                    end
                    3'b001: begin
                      alu_operator_o        = ALU_BEXTU;
                      imm_b_mux_sel_o       = IMMB_S2;
                      bmask_b_mux_o         = BMASK_B_ZERO;
                      alu_op_b_mux_sel_o    = OP_B_BMASK;
                    end
                    3'b010: begin
                      alu_operator_o        = ALU_BINS;
                      imm_b_mux_sel_o       = IMMB_S2;
                      regc_used_o           = 1'b1;
                      regc_mux_o            = REGC_RD;
                      alu_op_b_mux_sel_o    = OP_B_BMASK;
                      alu_bmask_b_mux_sel_o = BMASK_B_REG;
                    end
                    3'b100: begin
                      alu_operator_o        = ALU_BCLR;
                      alu_bmask_b_mux_sel_o = BMASK_B_REG;
                    end
                    3'b101: begin
                      alu_operator_o        = ALU_BSET;
                      alu_bmask_b_mux_sel_o = BMASK_B_REG;
                    end
                    default: illegal_insn_o = 1'b1;
                  endcase
                end

                7'b0100000, 7'b0100001, 7'b0100010, 7'b0100011,
                7'b0100100, 7'b0100101, 7'b0100110, 7'b0100111,
                7'b0101000, 7'b0101001, 7'b0101010, 7'b0101011,
                7'b0101100, 7'b0101101, 7'b0101110, 7'b0101111,
                7'b0110000, 7'b0110001, 7'b0110010, 7'b0110011,
                7'b0110100, 7'b0110101, 7'b0110110, 7'b0110111,
                7'b0111000, 7'b0111001, 7'b0111010, 7'b0111011,
                7'b0111100, 7'b0111101, 7'b0111110, 7'b0111111: begin
                  regfile_alu_we = 1'b1;
                  rega_used_o    = 1'b1;
                  regb_used_o    = 1'b1;

                  unique case (instr_rdata_i[29:25])
                    5'b00000: alu_operator_o = ALU_ROR;
                    5'b00001: begin
                      regb_used_o    = 1'b0;
                      alu_operator_o = ALU_FF1;
                      if (instr_rdata_i[24:20] != 5'b0) begin
                        illegal_insn_o = 1'b1;
                      end
                    end
                    5'b00010: begin
                      regb_used_o    = 1'b0;
                      alu_operator_o = ALU_FL1;
                      if (instr_rdata_i[24:20] != 5'b0) begin
                        illegal_insn_o = 1'b1;
                      end
                    end
                    5'b00011: begin
                      regb_used_o    = 1'b0;
                      alu_operator_o = ALU_CLB;
                      if (instr_rdata_i[24:20] != 5'b0) begin
                        illegal_insn_o = 1'b1;
                      end
                    end
                    5'b00100: begin
                      regb_used_o    = 1'b0;
                      alu_operator_o = ALU_CNT;
                      if (instr_rdata_i[24:20] != 5'b0) begin
                        illegal_insn_o = 1'b1;
                      end
                    end
                    5'b01000: begin
                      alu_operator_o = ALU_ABS;
                      if (instr_rdata_i[24:20] != 5'b0) begin
                        illegal_insn_o = 1'b1;
                      end
                    end
                    5'b01001: alu_operator_o = ALU_SLETS;
                    5'b01010: alu_operator_o = ALU_SLETU;
                    5'b01011: alu_operator_o = ALU_MIN;
                    5'b01100: alu_operator_o = ALU_MINU;
                    5'b01101: alu_operator_o = ALU_MAX;
                    5'b01110: alu_operator_o = ALU_MAXU;
                    5'b10000: begin
                      regb_used_o    = 1'b0;
                      alu_operator_o = ALU_EXTS;
                      alu_vec_mode_o = VEC_MODE16;
                      if (instr_rdata_i[24:20] != 5'b0) begin
                        illegal_insn_o = 1'b1;
                      end
                    end
                    5'b10001: begin
                      regb_used_o    = 1'b0;
                      alu_operator_o = ALU_EXT;
                      alu_vec_mode_o = VEC_MODE16;
                      if (instr_rdata_i[24:20] != 5'b0) begin
                        illegal_insn_o = 1'b1;
                      end
                    end
                    5'b10010: begin
                      regb_used_o    = 1'b0;
                      alu_operator_o = ALU_EXTS;
                      alu_vec_mode_o = VEC_MODE8;
                      if (instr_rdata_i[24:20] != 5'b0) begin
                        illegal_insn_o = 1'b1;
                      end
                    end
                    5'b10011: begin
                      regb_used_o    = 1'b0;
                      alu_operator_o = ALU_EXT;
                      alu_vec_mode_o = VEC_MODE8;
                      if (instr_rdata_i[24:20] != 5'b0) begin
                        illegal_insn_o = 1'b1;
                      end
                    end
                    5'b11000: begin
                      regb_used_o        = 1'b0;
                      alu_operator_o     = ALU_CLIP;
                      alu_op_b_mux_sel_o = OP_B_IMM;
                      imm_b_mux_sel_o    = IMMB_CLIP;
                    end
                    5'b11001: begin
                      regb_used_o        = 1'b0;
                      alu_operator_o     = ALU_CLIPU;
                      alu_op_b_mux_sel_o = OP_B_IMM;
                      imm_b_mux_sel_o    = IMMB_CLIP;
                    end
                    5'b11010: alu_operator_o = ALU_CLIP;
                    5'b11011: alu_operator_o = ALU_CLIPU;
                    default : illegal_insn_o = 1'b1;
                  endcase
                end

                7'b1000000, 7'b1000001, 7'b1000010, 7'b1000011,
                7'b1000100, 7'b1000101, 7'b1000110, 7'b1000111: begin
                  regfile_alu_we        = 1'b1;
                  rega_used_o           = 1'b1;
                  regb_used_o           = 1'b1;
                  regc_used_o           = 1'b1;
                  regc_mux_o            = REGC_RD;
                  bmask_a_mux_o         = BMASK_A_ZERO;
                  bmask_b_mux_o         = BMASK_B_S3;
                  alu_bmask_b_mux_sel_o = BMASK_B_REG;
                  alu_op_a_mux_sel_o    = OP_A_REGC_OR_FWD;
                  alu_op_b_mux_sel_o    = OP_B_REGA_OR_FWD;

                  unique case (instr_rdata_i[27:25])
                    3'b001:  alu_operator_o = ALU_ADDU;
                    3'b010:  alu_operator_o = ALU_ADDR;
                    3'b011:  alu_operator_o = ALU_ADDUR;
                    3'b100:  alu_operator_o = ALU_SUB;
                    3'b101:  alu_operator_o = ALU_SUBU;
                    3'b110:  alu_operator_o = ALU_SUBR;
                    3'b111:  alu_operator_o = ALU_SUBUR;
                    default: alu_operator_o = ALU_ADD;
                  endcase
                end

                7'b1001000, 7'b1001001: begin
                  alu_en          = 1'b0;
                  mult_int_en     = 1'b1;
                  regfile_alu_we  = 1'b1;
                  rega_used_o     = 1'b1;
                  regb_used_o     = 1'b1;
                  regc_used_o     = 1'b1;
                  regc_mux_o      = REGC_RD;

                  if (instr_rdata_i[25] == 1'b0) begin
                    mult_operator_o = MUL_MAC32;
                  end else begin
                    mult_operator_o = MUL_MSU32;
                  end
                end

                default: illegal_insn_o = 1'b1;
              endcase
            end

            3'b100 : begin
              hwlp_target_mux_sel_o = 2'b0;

              unique case (instr_rdata_i[11:8])
                4'b0000: begin

                  hwlp_we[0]           = 1'b1;
                  hwlp_start_mux_sel_o = 2'b0;
                  if (instr_rdata_i[19:15] != 5'b0) begin
                    illegal_insn_o = 1'b1;
                  end
                end
                4'b0001: begin

                  hwlp_we[0]           = 1'b1;
                  hwlp_start_mux_sel_o = 2'b10;
                  rega_used_o          = 1'b1;
                  if (instr_rdata_i[31:20] != 12'b0) begin
                    illegal_insn_o = 1'b1;
                  end
                end
                4'b0010: begin

                  hwlp_we[1] = 1'b1;
                  if (instr_rdata_i[19:15] != 5'b0) begin
                    illegal_insn_o = 1'b1;
                  end
                end
                4'b0011: begin

                  hwlp_we[1]            = 1'b1;
                  hwlp_target_mux_sel_o = 2'b10;
                  rega_used_o           = 1'b1;
                  if (instr_rdata_i[31:20] != 12'b0) begin
                    illegal_insn_o = 1'b1;
                  end
                end
                4'b0100: begin

                  hwlp_we[2]         = 1'b1;
                  hwlp_cnt_mux_sel_o = 1'b0;
                  if (instr_rdata_i[19:15] != 5'b0) begin
                    illegal_insn_o = 1'b1;
                  end
                end
                4'b0101: begin

                  hwlp_we[2]         = 1'b1;
                  hwlp_cnt_mux_sel_o = 1'b1;
                  rega_used_o        = 1'b1;
                  if (instr_rdata_i[31:20] != 12'b0) begin
                    illegal_insn_o = 1'b1;
                  end
                end
                4'b0110: begin

                  hwlp_we               = 3'b111;
                  hwlp_target_mux_sel_o = 2'b01;
                  hwlp_start_mux_sel_o  = 2'b01;
                  hwlp_cnt_mux_sel_o    = 1'b0;
                end
                4'b0111: begin

                  hwlp_we              = 3'b111;
                  hwlp_start_mux_sel_o = 2'b01;
                  hwlp_cnt_mux_sel_o   = 1'b1;
                  rega_used_o          = 1'b1;
                end
                default: begin
                  illegal_insn_o = 1'b1;
                end
              endcase
            end

            default: illegal_insn_o = 1'b1;
          endcase

        end else begin
          illegal_insn_o = 1'b1;
        end
      end

      OPCODE_CUSTOM_2: begin
        if (COREV_PULP) begin
          regfile_alu_we = 1'b1;
          rega_used_o    = 1'b1;
          regb_used_o    = 1'b1;

          unique case (instr_rdata_i[14:13])
            2'b00: begin

              regb_used_o         = 1'b0;
              bmask_a_mux_o       = BMASK_A_S3;
              bmask_b_mux_o       = BMASK_B_S2;
              alu_op_b_mux_sel_o  = OP_B_IMM;

              unique case ({instr_rdata_i[31:30], instr_rdata_i[12]})
                {2'b00, 1'b0}: begin
                  alu_operator_o  = ALU_BEXT;
                  imm_b_mux_sel_o = IMMB_S2;
                  bmask_b_mux_o   = BMASK_B_ZERO;
                end
                {2'b01, 1'b0}: begin
                  alu_operator_o  = ALU_BEXTU;
                  imm_b_mux_sel_o = IMMB_S2;
                  bmask_b_mux_o   = BMASK_B_ZERO;
                end
                {2'b10, 1'b0}: begin
                  alu_operator_o  = ALU_BINS;
                  imm_b_mux_sel_o = IMMB_S2;
                  regc_used_o     = 1'b1;
                  regc_mux_o      = REGC_RD;
                end
                {2'b00, 1'b1}: begin
                  alu_operator_o = ALU_BCLR;
                end
                {2'b01, 1'b1}: begin
                  alu_operator_o = ALU_BSET;
                end
                {2'b11, 1'b1}: begin
                  alu_operator_o        = ALU_BREV;

                  regc_used_o           = 1'b1;
                  regc_mux_o            = REGC_RD;

                  imm_b_mux_sel_o       = IMMB_S2;

                  alu_bmask_a_mux_sel_o = BMASK_A_IMM;
                  if (instr_rdata_i[29:27] != 3'b0) begin
                    illegal_insn_o = 1'b1;
                  end
                end
                default: illegal_insn_o = 1'b1;
              endcase
            end

            2'b01: begin

              bmask_a_mux_o  = BMASK_A_ZERO;
              bmask_b_mux_o  = BMASK_B_S3;

              unique case ({instr_rdata_i[31:30], instr_rdata_i[12]})
                {2'b01, 1'b0}: alu_operator_o = ALU_ADDU;
                {2'b10, 1'b0}: alu_operator_o = ALU_ADDR;
                {2'b11, 1'b0}: alu_operator_o = ALU_ADDUR;
                {2'b00, 1'b1}: alu_operator_o = ALU_SUB;
                {2'b01, 1'b1}: alu_operator_o = ALU_SUBU;
                {2'b10, 1'b1}: alu_operator_o = ALU_SUBR;
                {2'b11, 1'b1}: alu_operator_o = ALU_SUBUR;
                default      : alu_operator_o = ALU_ADD;
              endcase

            end

            default: begin

              alu_en             = 1'b0;
              mult_int_en        = 1'b1;

              mult_imm_mux_o     = MIMM_S3;
              mult_sel_subword_o = instr_rdata_i[30];

              mult_signed_mode_o = {2{~instr_rdata_i[12]}};

              if (instr_rdata_i[13]) begin

                regc_used_o = 1'b1;
                regc_mux_o  = REGC_RD;
              end else begin

                regc_mux_o  = REGC_ZERO;
              end

              if (instr_rdata_i[31]) begin

                mult_operator_o = MUL_IR;
              end else begin

                mult_operator_o = MUL_I;
              end
            end
          endcase
        end else begin
          illegal_insn_o = 1'b1;
        end
      end

      OPCODE_CUSTOM_3: begin
        if (COREV_PULP) begin
          regfile_alu_we      = 1'b1;
          rega_used_o         = 1'b1;
          imm_b_mux_sel_o     = IMMB_VS;

          alu_vec_o = 1'b1;

          if (instr_rdata_i[12]) begin
            alu_vec_mode_o  = VEC_MODE8;
            mult_operator_o = MUL_DOT8;
          end else begin
            alu_vec_mode_o  = VEC_MODE16;
            mult_operator_o = MUL_DOT16;
          end

          if (instr_rdata_i[14]) begin
            scalar_replication_o = 1'b1;

            if (instr_rdata_i[13]) begin

              alu_op_b_mux_sel_o = OP_B_IMM;
            end else begin

              regb_used_o = 1'b1;
            end
          end else begin

            regb_used_o = 1'b1;
          end

          unique case (instr_rdata_i[31:26])
            6'b00000_0: begin
              alu_operator_o = ALU_ADD;
              imm_b_mux_sel_o = IMMB_VS;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b00001_0: begin
              alu_operator_o = ALU_SUB;
              imm_b_mux_sel_o = IMMB_VS;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b00010_0: begin
              alu_operator_o = ALU_ADD;
              imm_b_mux_sel_o = IMMB_VS;
              bmask_b_mux_o = BMASK_B_ONE;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b00011_0: begin
             alu_operator_o = ALU_ADDU;
             imm_b_mux_sel_o = IMMB_VU;
             bmask_b_mux_o = BMASK_B_ONE;
             if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
               illegal_insn_o = 1'b1;
             end
             if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                 instr_rdata_i[25] != 1'b0) begin
               illegal_insn_o = 1'b1;
             end
            end
            6'b00100_0: begin
             alu_operator_o = ALU_MIN;
             imm_b_mux_sel_o = IMMB_VS;
             if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
               illegal_insn_o = 1'b1;
             end
             if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                 instr_rdata_i[25] != 1'b0) begin
               illegal_insn_o = 1'b1;
             end
            end
            6'b00101_0: begin
              alu_operator_o = ALU_MINU;
              imm_b_mux_sel_o = IMMB_VU;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b00110_0: begin
              alu_operator_o = ALU_MAX;
              imm_b_mux_sel_o = IMMB_VS;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b00111_0: begin
              alu_operator_o = ALU_MAXU;
              imm_b_mux_sel_o = IMMB_VU;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b01000_0: begin
              alu_operator_o = ALU_SRL;
              imm_b_mux_sel_o = IMMB_VS;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end

              if ((instr_rdata_i[14:12] == 3'b110 && instr_rdata_i[24:23] != 2'b0) ||
                  (instr_rdata_i[14:12] == 3'b111 && instr_rdata_i[24:22] != 3'b0)) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b01001_0: begin
              alu_operator_o = ALU_SRA;
              imm_b_mux_sel_o = IMMB_VS;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end

              if ((instr_rdata_i[14:12] == 3'b110 && instr_rdata_i[24:23] != 2'b0) ||
                  (instr_rdata_i[14:12] == 3'b111 && instr_rdata_i[24:22] != 3'b0)) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b01010_0: begin
              alu_operator_o = ALU_SLL;
              imm_b_mux_sel_o = IMMB_VS;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end

              if ((instr_rdata_i[14:12] == 3'b110 && instr_rdata_i[24:23] != 2'b0) ||
                  (instr_rdata_i[14:12] == 3'b111 && instr_rdata_i[24:22] != 3'b0)) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b01011_0: begin
              alu_operator_o = ALU_OR;
              imm_b_mux_sel_o = IMMB_VS;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b01100_0: begin
              alu_operator_o = ALU_XOR;
              imm_b_mux_sel_o = IMMB_VS;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b01101_0: begin
              alu_operator_o = ALU_AND;
              imm_b_mux_sel_o = IMMB_VS;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b01110_0: begin
              alu_operator_o = ALU_ABS;
              imm_b_mux_sel_o = IMMB_VS;
              if (instr_rdata_i[14:12] != 3'b000 && instr_rdata_i[14:12] != 3'b001) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[25:20] != 6'b000000) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b10000_0: begin
              alu_en            = 1'b0;
              mult_dot_en       = 1'b1;
              mult_dot_signed_o = 2'b00;
              imm_b_mux_sel_o   = IMMB_VU;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b10001_0: begin
              alu_en            = 1'b0;
              mult_dot_en       = 1'b1;
              mult_dot_signed_o = 2'b01;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b10010_0: begin
              alu_en            = 1'b0;
              mult_dot_en       = 1'b1;
              mult_dot_signed_o = 2'b11;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b10011_0: begin
              alu_en            = 1'b0;
              mult_dot_en       = 1'b1;
              mult_dot_signed_o = 2'b00;
              regc_used_o       = 1'b1;
              regc_mux_o        = REGC_RD;
              imm_b_mux_sel_o   = IMMB_VU;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b10100_0: begin
              alu_en            = 1'b0;
              mult_dot_en       = 1'b1;
              mult_dot_signed_o = 2'b01;
              regc_used_o       = 1'b1;
              regc_mux_o        = REGC_RD;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b10101_0: begin
              alu_en            = 1'b0;
              mult_dot_en       = 1'b1;
              mult_dot_signed_o = 2'b11;
              regc_used_o       = 1'b1;
              regc_mux_o        = REGC_RD;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b10111_0: begin
              unique case (instr_rdata_i[14:13])
                2'b00: alu_operator_o = ALU_EXTS;
                2'b01: alu_operator_o = ALU_EXT;
                2'b10: begin
                  alu_operator_o     = ALU_INS;
                  regc_used_o        = 1'b1;
                  regc_mux_o         = REGC_RD;
                  alu_op_b_mux_sel_o = OP_B_REGC_OR_FWD;
                end
                default: illegal_insn_o = 1'b1;
              endcase

              if ((instr_rdata_i[12] == 1'b0 && instr_rdata_i[24:20] != 5'b0) ||
                  (instr_rdata_i[12] == 1'b1 && instr_rdata_i[24:21] != 4'b0)) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b11000_0: begin
              alu_operator_o       = ALU_SHUF;
              imm_b_mux_sel_o      = IMMB_SHUF;
              regb_used_o          = 1'b1;
              scalar_replication_o = 1'b0;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011 ||
                  instr_rdata_i[14:12] == 3'b100 || instr_rdata_i[14:12] == 3'b101) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end

              if (instr_rdata_i[14:12] == 3'b110 && instr_rdata_i[24:21] != 4'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b11001_0,
            6'b11010_0,
            6'b11011_0: begin
              alu_operator_o       = ALU_SHUF;
              imm_b_mux_sel_o      = IMMB_SHUF;
              regb_used_o          = 1'b1;
              scalar_replication_o = 1'b0;
              if (instr_rdata_i[14:12] != 3'b111) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b11100_0: begin
              alu_operator_o       = ALU_SHUF2;
              regb_used_o          = 1'b1;
              regc_used_o          = 1'b1;
              regc_mux_o           = REGC_RD;
              scalar_replication_o = 1'b0;
              if (instr_rdata_i[14:12] != 3'b000 && instr_rdata_i[14:12] != 3'b001) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b11110_0: begin
              alu_operator_o = instr_rdata_i[25] ? ALU_PCKHI : ALU_PCKLO;
              regb_used_o    = 1'b1;
              if (instr_rdata_i[14:12] != 3'b000) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b11111_0: begin
              alu_operator_o = instr_rdata_i[25] ? ALU_PCKHI : ALU_PCKLO;
              regb_used_o    = 1'b1;
              regc_used_o    = 1'b1;
              regc_mux_o     = REGC_RD;
              if (instr_rdata_i[14:12] != 3'b001) begin
                illegal_insn_o = 1'b1;
              end
            end

            6'b00000_1: begin
              alu_operator_o  = ALU_EQ;
              imm_b_mux_sel_o = IMMB_VS;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b00001_1: begin
              alu_operator_o  = ALU_NE;
              imm_b_mux_sel_o = IMMB_VS;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b00010_1: begin
              alu_operator_o  = ALU_GTS;
              imm_b_mux_sel_o = IMMB_VS;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b00011_1: begin
              alu_operator_o  = ALU_GES;
              imm_b_mux_sel_o = IMMB_VS;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b00100_1: begin
              alu_operator_o  = ALU_LTS;
              imm_b_mux_sel_o = IMMB_VS;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b00101_1: begin
              alu_operator_o  = ALU_LES;
              imm_b_mux_sel_o = IMMB_VS;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b00110_1: begin
              alu_operator_o  = ALU_GTU;
              imm_b_mux_sel_o = IMMB_VU;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b00111_1: begin
              alu_operator_o  = ALU_GEU;
              imm_b_mux_sel_o = IMMB_VU;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b01000_1: begin
              alu_operator_o  = ALU_LTU;
              imm_b_mux_sel_o = IMMB_VU;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b01001_1: begin
              alu_operator_o  = ALU_LEU;
              imm_b_mux_sel_o = IMMB_VU;
              if (instr_rdata_i[14:12] == 3'b010 || instr_rdata_i[14:12] == 3'b011) begin
                illegal_insn_o = 1'b1;
              end
              if (instr_rdata_i[14:12] != 3'b110 && instr_rdata_i[14:12] != 3'b111 &&
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end

            6'b01010_1: begin
              alu_en               = 1'b0;
              mult_dot_en          = 1'b1;
              mult_dot_signed_o    = 2'b11;
              is_clpx_o            = 1'b1;
              regc_used_o          = 1'b1;
              regc_mux_o           = REGC_RD;
              scalar_replication_o = 1'b0;
              alu_op_b_mux_sel_o   = OP_B_REGB_OR_FWD;
              regb_used_o          = 1'b1;
              illegal_insn_o       = instr_rdata_i[12];
            end
            6'b01011_1: begin
              alu_operator_o       = ALU_ABS;
              is_clpx_o            = 1'b1;
              scalar_replication_o = 1'b0;
              regb_used_o          = 1'b0;
              if (instr_rdata_i[14:12] != 3'b000 || instr_rdata_i[25:20] != 6'b000000) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b01100_1: begin
              alu_operator_o       = ALU_SUB;
              is_clpx_o            = 1'b1;
              scalar_replication_o = 1'b0;
              alu_op_b_mux_sel_o   = OP_B_REGB_OR_FWD;
              regb_used_o          = 1'b1;
              is_subrot_o          = 1'b1;
              if (instr_rdata_i[12] != 1'b0 || instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b01101_1: begin
              alu_operator_o       = ALU_ADD;
              is_clpx_o            = 1'b1;
              scalar_replication_o = 1'b0;
              alu_op_b_mux_sel_o   = OP_B_REGB_OR_FWD;
              regb_used_o          = 1'b1;
              if (instr_rdata_i[12] != 1'b0 || instr_rdata_i[14:12] == 3'b000 ||
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end
            6'b01110_1: begin
              alu_operator_o       = ALU_SUB;
              is_clpx_o            = 1'b1;
              scalar_replication_o = 1'b0;
              alu_op_b_mux_sel_o   = OP_B_REGB_OR_FWD;
              regb_used_o          = 1'b1;
              if (instr_rdata_i[12] != 1'b0 || instr_rdata_i[14:12] == 3'b000 ||
                  instr_rdata_i[25] != 1'b0) begin
                illegal_insn_o = 1'b1;
              end
            end

            default: illegal_insn_o = 1'b1;
          endcase
        end else begin
          illegal_insn_o = 1'b1;
        end
      end

      OPCODE_FENCE: begin
        unique case (instr_rdata_i[14:12])
          3'b000: begin

            fencei_insn_o = 1'b1;
          end

          3'b001: begin

            fencei_insn_o = 1'b1;
          end

          default: illegal_insn_o =  1'b1;
        endcase
      end

      OPCODE_SYSTEM: begin
        if (instr_rdata_i[14:12] == 3'b000)
        begin

          if ( {instr_rdata_i[19:15], instr_rdata_i[11:7]} == '0)
          begin
            unique case (instr_rdata_i[31:20])
              12'h000:
              begin

                ecall_insn_o  = 1'b1;
              end

              12'h001:
              begin

                ebrk_insn_o = 1'b1;
              end

              12'h302:
              begin
                illegal_insn_o = (PULP_SECURE) ? current_priv_lvl_i != PRIV_LVL_M : 1'b0;
                mret_insn_o    = ~illegal_insn_o;
                mret_dec_o     = 1'b1;
              end

              12'h002:
              begin
                illegal_insn_o = (PULP_SECURE) ? 1'b0 : 1'b1;
                uret_insn_o    = ~illegal_insn_o;
                uret_dec_o     = 1'b1;
              end

              12'h7b2:
              begin
                illegal_insn_o = !debug_mode_i;
                dret_insn_o    =  debug_mode_i;
                dret_dec_o     =  1'b1;
              end

              12'h105:
              begin
                wfi_o = 1'b1;
                if (debug_wfi_no_sleep_i) begin

                  alu_op_b_mux_sel_o = OP_B_IMM;
                  imm_b_mux_sel_o = IMMB_I;
                  alu_operator_o = ALU_ADD;
                end
              end

              default: illegal_insn_o = 1'b1;
            endcase
          end else illegal_insn_o = 1'b1;
        end
        else
        begin

          csr_access_o        = 1'b1;
          regfile_alu_we      = 1'b1;
          alu_op_b_mux_sel_o  = OP_B_IMM;
          imm_a_mux_sel_o     = IMMA_Z;
          imm_b_mux_sel_o     = IMMB_I;

          if (instr_rdata_i[14] == 1'b1) begin

            alu_op_a_mux_sel_o = OP_A_IMM;
          end else begin
            rega_used_o        = 1'b1;
            alu_op_a_mux_sel_o = OP_A_REGA_OR_FWD;
          end

          unique case (instr_rdata_i[13:12])
            2'b01:   csr_op = CSR_OP_WRITE;
            2'b10:   csr_op = instr_rdata_i[19:15] == 5'b0 ? CSR_OP_READ : CSR_OP_SET;
            2'b11:   csr_op = instr_rdata_i[19:15] == 5'b0 ? CSR_OP_READ : CSR_OP_CLEAR;
            default: csr_illegal = 1'b1;
          endcase

          if (instr_rdata_i[29:28] > current_priv_lvl_i) begin

            csr_illegal = 1'b1;
          end

          case (instr_rdata_i[31:20])

            CSR_FFLAGS :
                if (FPU == 0 || fs_off_i == 1'b1) csr_illegal = 1'b1;

            CSR_FRM,
              CSR_FCSR :
                if (FPU == 0 || fs_off_i == 1'b1) begin
                  csr_illegal = 1'b1;
                end else begin

                  if (csr_op != CSR_OP_READ) csr_status_o = 1'b1;
                end

            CSR_MVENDORID,
              CSR_MARCHID,
              CSR_MIMPID,
              CSR_MHARTID :
                if (csr_op != CSR_OP_READ) csr_illegal = 1'b1;

            CSR_MSTATUS,
              CSR_MEPC,
              CSR_MTVEC,
              CSR_MCAUSE :

                csr_status_o = 1'b1;

            CSR_MISA,
              CSR_MIE,
              CSR_MSCRATCH,
              CSR_MTVAL,
              CSR_MIP :
                ;

            CSR_MCYCLE,
              CSR_MINSTRET,
              CSR_MHPMCOUNTER3,
              CSR_MHPMCOUNTER4,  CSR_MHPMCOUNTER5,  CSR_MHPMCOUNTER6,  CSR_MHPMCOUNTER7,
              CSR_MHPMCOUNTER8,  CSR_MHPMCOUNTER9,  CSR_MHPMCOUNTER10, CSR_MHPMCOUNTER11,
              CSR_MHPMCOUNTER12, CSR_MHPMCOUNTER13, CSR_MHPMCOUNTER14, CSR_MHPMCOUNTER15,
              CSR_MHPMCOUNTER16, CSR_MHPMCOUNTER17, CSR_MHPMCOUNTER18, CSR_MHPMCOUNTER19,
              CSR_MHPMCOUNTER20, CSR_MHPMCOUNTER21, CSR_MHPMCOUNTER22, CSR_MHPMCOUNTER23,
              CSR_MHPMCOUNTER24, CSR_MHPMCOUNTER25, CSR_MHPMCOUNTER26, CSR_MHPMCOUNTER27,
              CSR_MHPMCOUNTER28, CSR_MHPMCOUNTER29, CSR_MHPMCOUNTER30, CSR_MHPMCOUNTER31,
              CSR_MCYCLEH,
              CSR_MINSTRETH,
              CSR_MHPMCOUNTER3H,
              CSR_MHPMCOUNTER4H,  CSR_MHPMCOUNTER5H,  CSR_MHPMCOUNTER6H,  CSR_MHPMCOUNTER7H,
              CSR_MHPMCOUNTER8H,  CSR_MHPMCOUNTER9H,  CSR_MHPMCOUNTER10H, CSR_MHPMCOUNTER11H,
              CSR_MHPMCOUNTER12H, CSR_MHPMCOUNTER13H, CSR_MHPMCOUNTER14H, CSR_MHPMCOUNTER15H,
              CSR_MHPMCOUNTER16H, CSR_MHPMCOUNTER17H, CSR_MHPMCOUNTER18H, CSR_MHPMCOUNTER19H,
              CSR_MHPMCOUNTER20H, CSR_MHPMCOUNTER21H, CSR_MHPMCOUNTER22H, CSR_MHPMCOUNTER23H,
              CSR_MHPMCOUNTER24H, CSR_MHPMCOUNTER25H, CSR_MHPMCOUNTER26H, CSR_MHPMCOUNTER27H,
              CSR_MHPMCOUNTER28H, CSR_MHPMCOUNTER29H, CSR_MHPMCOUNTER30H, CSR_MHPMCOUNTER31H,
              CSR_MCOUNTINHIBIT,
              CSR_MHPMEVENT3,
              CSR_MHPMEVENT4,  CSR_MHPMEVENT5,  CSR_MHPMEVENT6,  CSR_MHPMEVENT7,
              CSR_MHPMEVENT8,  CSR_MHPMEVENT9,  CSR_MHPMEVENT10, CSR_MHPMEVENT11,
              CSR_MHPMEVENT12, CSR_MHPMEVENT13, CSR_MHPMEVENT14, CSR_MHPMEVENT15,
              CSR_MHPMEVENT16, CSR_MHPMEVENT17, CSR_MHPMEVENT18, CSR_MHPMEVENT19,
              CSR_MHPMEVENT20, CSR_MHPMEVENT21, CSR_MHPMEVENT22, CSR_MHPMEVENT23,
              CSR_MHPMEVENT24, CSR_MHPMEVENT25, CSR_MHPMEVENT26, CSR_MHPMEVENT27,
              CSR_MHPMEVENT28, CSR_MHPMEVENT29, CSR_MHPMEVENT30, CSR_MHPMEVENT31 :

                csr_status_o = 1'b1;

            CSR_CYCLE,
              CSR_INSTRET,
              CSR_HPMCOUNTER3,
              CSR_HPMCOUNTER4,  CSR_HPMCOUNTER5,  CSR_HPMCOUNTER6,  CSR_HPMCOUNTER7,
              CSR_HPMCOUNTER8,  CSR_HPMCOUNTER9,  CSR_HPMCOUNTER10, CSR_HPMCOUNTER11,
              CSR_HPMCOUNTER12, CSR_HPMCOUNTER13, CSR_HPMCOUNTER14, CSR_HPMCOUNTER15,
              CSR_HPMCOUNTER16, CSR_HPMCOUNTER17, CSR_HPMCOUNTER18, CSR_HPMCOUNTER19,
              CSR_HPMCOUNTER20, CSR_HPMCOUNTER21, CSR_HPMCOUNTER22, CSR_HPMCOUNTER23,
              CSR_HPMCOUNTER24, CSR_HPMCOUNTER25, CSR_HPMCOUNTER26, CSR_HPMCOUNTER27,
              CSR_HPMCOUNTER28, CSR_HPMCOUNTER29, CSR_HPMCOUNTER30, CSR_HPMCOUNTER31,
              CSR_CYCLEH,
              CSR_INSTRETH,
              CSR_HPMCOUNTER3H,
              CSR_HPMCOUNTER4H,  CSR_HPMCOUNTER5H,  CSR_HPMCOUNTER6H,  CSR_HPMCOUNTER7H,
              CSR_HPMCOUNTER8H,  CSR_HPMCOUNTER9H,  CSR_HPMCOUNTER10H, CSR_HPMCOUNTER11H,
              CSR_HPMCOUNTER12H, CSR_HPMCOUNTER13H, CSR_HPMCOUNTER14H, CSR_HPMCOUNTER15H,
              CSR_HPMCOUNTER16H, CSR_HPMCOUNTER17H, CSR_HPMCOUNTER18H, CSR_HPMCOUNTER19H,
              CSR_HPMCOUNTER20H, CSR_HPMCOUNTER21H, CSR_HPMCOUNTER22H, CSR_HPMCOUNTER23H,
              CSR_HPMCOUNTER24H, CSR_HPMCOUNTER25H, CSR_HPMCOUNTER26H, CSR_HPMCOUNTER27H,
              CSR_HPMCOUNTER28H, CSR_HPMCOUNTER29H, CSR_HPMCOUNTER30H, CSR_HPMCOUNTER31H :

                if ((csr_op != CSR_OP_READ) ||
                    (PULP_SECURE && (current_priv_lvl_i != PRIV_LVL_M) && !mcounteren_i[instr_rdata_i[24:20]])) begin
                  csr_illegal = 1'b1;
                end else begin
                  csr_status_o = 1'b1;
                end

            CSR_MCOUNTEREN :
                if (!PULP_SECURE) begin
                  csr_illegal = 1'b1;
                end else begin
                  csr_status_o = 1'b1;
                end

            CSR_DCSR,
              CSR_DPC,
              CSR_DSCRATCH0,
              CSR_DSCRATCH1 :
                if (!debug_mode_i) begin
                  csr_illegal = 1'b1;
                end else begin
                  csr_status_o = 1'b1;
                end

            CSR_TSELECT,
              CSR_TDATA1,
              CSR_TDATA2,
              CSR_TDATA3,
              CSR_TINFO,
              CSR_MCONTEXT,
              CSR_SCONTEXT :
                if (DEBUG_TRIGGER_EN != 1)
                  csr_illegal = 1'b1;

            CSR_LPSTART0,
              CSR_LPEND0,
              CSR_LPCOUNT0,
              CSR_LPSTART1,
              CSR_LPEND1,
              CSR_LPCOUNT1:
                if (!COREV_PULP || csr_op != CSR_OP_READ) csr_illegal = 1'b1;

            CSR_UHARTID :
                if (!COREV_PULP || csr_op != CSR_OP_READ) csr_illegal = 1'b1;

            CSR_PRIVLV :
                if (!COREV_PULP || csr_op != CSR_OP_READ) begin
                  csr_illegal = 1'b1;
                end else begin
                  csr_status_o = 1'b1;
                end

            CSR_ZFINX :
                if (!COREV_PULP || (FPU && !ZFINX) || csr_op != CSR_OP_READ) begin
                  csr_illegal = 1'b1;
                end

            CSR_PMPCFG0,
              CSR_PMPCFG1,
              CSR_PMPCFG2,
              CSR_PMPCFG3,
              CSR_PMPADDR0,
              CSR_PMPADDR1,
              CSR_PMPADDR2,
              CSR_PMPADDR3,
              CSR_PMPADDR4,
              CSR_PMPADDR5,
              CSR_PMPADDR6,
              CSR_PMPADDR7,
              CSR_PMPADDR8,
              CSR_PMPADDR9,
              CSR_PMPADDR10,
              CSR_PMPADDR11,
              CSR_PMPADDR12,
              CSR_PMPADDR13,
              CSR_PMPADDR14,
              CSR_PMPADDR15 :
                if (!USE_PMP) csr_illegal = 1'b1;

            CSR_USTATUS,
              CSR_UEPC,
              CSR_UTVEC,
              CSR_UCAUSE :
                if (!PULP_SECURE) begin
                  csr_illegal = 1'b1;
                end else begin
                  csr_status_o = 1'b1;
                end

            default : csr_illegal = 1'b1;

          endcase

          illegal_insn_o = csr_illegal;

        end
      end
      default: illegal_insn_o = 1'b1;
    endcase

    if (illegal_c_insn_i) begin
      illegal_insn_o = 1'b1;
    end

  end

  assign alu_en_o                    = (deassert_we_i) ? 1'b0          : alu_en;
  assign mult_int_en_o               = (deassert_we_i) ? 1'b0          : mult_int_en;
  assign mult_dot_en_o               = (deassert_we_i) ? 1'b0          : mult_dot_en;
  assign apu_en_o                    = (deassert_we_i) ? 1'b0          : apu_en;
  assign regfile_mem_we_o            = (deassert_we_i) ? 1'b0          : regfile_mem_we;
  assign regfile_alu_we_o            = (deassert_we_i) ? 1'b0          : regfile_alu_we;
  assign data_req_o                  = (deassert_we_i) ? 1'b0          : data_req;
  assign hwlp_we_o                   = (deassert_we_i) ? 3'b0          : hwlp_we;
  assign csr_op_o                    = (deassert_we_i) ? CSR_OP_READ   : csr_op;
  assign ctrl_transfer_insn_in_id_o  = (deassert_we_i) ? BRANCH_NONE   : ctrl_transfer_insn;

  assign ctrl_transfer_insn_in_dec_o  = ctrl_transfer_insn;
  assign regfile_alu_we_dec_o         = regfile_alu_we;

endmodule
