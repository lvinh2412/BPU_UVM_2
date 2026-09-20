//------------------------------------------------------------------------------
// FILE: tests/t12_correction_tests.sv -- Nhom 12: Correction
//   12.1 corr_target_matrix
//   12.2 corr_flush_decoupling
//------------------------------------------------------------------------------


//==============================================================================
// 12.1 corr_target_matrix
// Sheet -- Flow: quet ma tran (predicted_taken, branch_taken, pred_was_hit), moi
//   o day nhanh qua du ba tang.
// Sheet -- Pass: corr_valid=1 chi khi is_branch=1 va predicted_taken khac
//   branch_taken. taken=0 -> pc+4 voi CA HAI pred_was_hit (ban decode dung
//   nxpc+4); taken=1 & hit=1 -> btb_target_pc; taken=1 & hit=0 -> pc + offset.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class corr_target_matrix_test extends bpu_scene_base;
  `bpu_test_utils(corr_target_matrix_test, "12.1")

  string tbl;

  // Mot o co hieu chinh: kiem canh, valid=1, dia chi hieu chinh, ghi vao bang.
  local task automatic corr_cell(string lbl, bit [31:0] pc, bit [31:0] nxpc2, bit taken, bit [6:0] opc,
                                 bit [31:0] offset, bit exp_hit, bit exp_predT, bit [31:0] exp, string kind);
    bpu_pipe_obs_t o[4];
    pipe_probe(.pc(pc), .nxpc2(nxpc2), .taken(taken), .opc(opc), .offset(offset), .o(o));
    assert_cell(lbl, o[2], exp_hit, exp_predT);
    chk(o[2].bpu_nxpc2_valid === 1'b1, {lbl, ": valid != 1"});
    chk(o[2].bpu_nxpc2 === exp, $sformatf("%s: nxpc2=0x%08h, ky vong %s=0x%08h", lbl, o[2].bpu_nxpc2, kind, exp));
    tbl = {tbl, $sformatf("  |  %0d  |   %0d   |  %0d   | 0x%08h | %s\n", exp_hit, exp_predT, taken, o[2].bpu_nxpc2, kind)};
  endtask

  virtual task test_body();
    bpu_pipe_obs_t o[4];
    setup_addresses();
    tbl = "";

    //---- A: du doan DUNG -> corr_valid = 0 ---------------------------------
    phase_of("A_correct_predict_no_correction");
    pipe_probe(.pc(ADDR_TK), .nxpc2(ADDR_TK), .taken(1'b1), .o(o));
    assert_cell("hit=1 predT actT", o[2], 1'b1, 1'b1);
    chk(o[2].bpu_nxpc2_valid === 1'b0, $sformatf("du doan dung (predT=actT=1): valid=%0d, ky vong 0", o[2].bpu_nxpc2_valid));
    pipe_probe(.pc(ADDR_NT), .nxpc2(ADDR_NT), .taken(1'b0), .o(o));
    assert_cell("hit=1 predNT actNT", o[2], 1'b1, 1'b0);
    chk(o[2].bpu_nxpc2_valid === 1'b0, $sformatf("du doan dung (predNT=actNT): valid=%0d, ky vong 0", o[2].bpu_nxpc2_valid));

    //---- B: taken = 0 -> pc + 4, voi CA HAI gia tri pred_was_hit -----------
    phase_of("B_not_taken_gives_pc_plus_4");
    corr_cell("hit=1 predT actNT", ADDR_TK, ADDR_TK, 1'b0, OPC_NOP, 32'h40, 1'b1, 1'b1, ADDR_TK + 32'd4, "pc+4");
    corr_cell("hit=0 predT actNT", 32'h0000_04C0, ADDR_UT, 1'b0, OPC_BR, 32'h40, 1'b0, 1'b1, 32'h0000_04C0 + 32'd4, "pc+4");

    //---- C: taken = 1, hit = 1 -> btb_target_pc -----------------------------
    phase_of("C_taken_hit_gives_btb_target_pc");
    refresh_nt();
    corr_cell("hit=1 predNT actT", ADDR_NT, ADDR_NT, 1'b1, OPC_NOP, 32'h40, 1'b1, 1'b0,
              bd.read_btb_target(bpu_idx(ADDR_NT)), "btb_target_pc");

    //---- D: taken = 1, hit = 0 -> pc + branch_offset (DUONG MOI) ------------
    // BTB miss tai fetch VA chan tang du phong tai F+1 (opcode ADDI).
    phase_of("D_taken_miss_gives_pc_plus_offset");
    corr_cell("hit=0 predNT actT", 32'h0000_04D0, ADDR_UT, 1'b1, OPC_NOP, 32'h0000_0084, 1'b0, 1'b0,
              32'h0000_04D0 + 32'h0000_0084, "pc+branch_offset (MOI)");

    //---- E: is_branch = 0 -> khong bao gio hieu chinh -----------------------
    phase_of("E_no_branch_no_correction");
    pipe_probe(.pc(ADDR_TK), .nxpc2(ADDR_TK), .taken(1'b0), .is_branch(1'b0), .o(o));
    chk(o[2].bpu_nxpc2_valid === 1'b0, $sformatf("is_branch=0: valid=%0d, ky vong 0 du carry-down bao du doan RE", o[2].bpu_nxpc2_valid));

    note({"\n======== MA TRAN DIA CHI HIEU CHINH ========\n",
          "  | hit | predT | actT |   corr_nxpc2  | dang\n",
          "  |-----|-------|------|---------------|---------------\n", tbl,
          "  Co so tinh la pc (ban decode dung nxpc).\n",
          "============================================"});
  endtask
endclass : corr_target_matrix_test


//==============================================================================
// 12.2 corr_flush_decoupling      --- MUC DIEU TRA (DesignNotes R3)
// Sheet -- Flow: TH A: backstop du doan DUNG (pred_was_hit=0, predicted_taken=1,
//   branch_taken=1). TH B: btb_valid_nxpc2=0 tai F va CHAN backstop tai F+1,
//   tai execute cap branch_taken=1.
// Sheet -- Pass: TH A: bpu_flush=1 kem corr_valid=0. TH B: bpu_flush=1 DONG
//   THOI corr_valid=1 va corr_nxpc2 = pc + branch_offset; ghi nhan de doi chieu
//   voi loi xem MOT bong bong co du hay khong.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class corr_flush_decoupling_test extends bpu_scene_base;
  `bpu_test_utils(corr_flush_decoupling_test, "12.2")

  virtual task test_body();
    bpu_pipe_obs_t oA[4], oB[4];
    bit [31:0] expB;
    setup_addresses();

    //---- TH A: backstop chuyen huong DUNG -> flush=1 nhung KHONG corr -------
    phase_of("A_backstop_correct_flush1_no_corr");
    pipe_probe(.pc(32'h0000_04E0), .nxpc2(ADDR_UT), .taken(1'b1), .opc(OPC_BR), .o(oA));   // BCC + pc chua gap -> d_valid=1
    assert_cell("TH A", oA[2], .exp_hit(1'b0), .exp_predT(1'b1));
    chk(oA[2].bpu_flush === 2'd1, $sformatf("TH A: bpu_flush=%0d, ky vong 1", oA[2].bpu_flush));
    chk(oA[2].bpu_nxpc2_valid === 1'b0, $sformatf("TH A: valid=%0d, ky vong 0 (corr_valid=0 vi du doan DUNG)", oA[2].bpu_nxpc2_valid));

    //---- TH B (R3): flush=1 DONG THOI corr_valid=1 --------------------------
    // BTB truot tai F VA backstop bi chan tai F+1 (opcode ADDI) -> predicted_taken=0,
    // pred_was_hit=0; cap branch_taken=1 tai execute.
    phase_of("B_R3_flush1_with_correction");
    pipe_probe(.pc(32'h0000_04F0), .nxpc2(ADDR_UT), .taken(1'b1), .offset(32'h0000_0064), .o(oB));
    assert_cell("TH B", oB[2], .exp_hit(1'b0), .exp_predT(1'b0));
    expB = 32'h0000_04F0 + 32'h0000_0064;
    note($sformatf({
      "\n=== DIEU TRA DesignNotes R3: flush=1 dong thoi corr_valid=1 ===\n",
      "  Dieu kien tai hien: F: btb_valid_nxpc2=0 ; F+1: backstop BI CHAN ; F+2: is_branch=1, branch_taken=1\n",
      "  Ket qua do duoc:\n",
      "    pred_was_hit    = %0d\n",
      "    predicted_taken = %0d\n",
      "    bpu_flush       = %0d   <- quy tac !pred_was_hit -> taken ? 1 : 2\n",
      "    corr_valid      = %0d   <- mispredict vi predicted_taken != branch_taken\n",
      "    corr_nxpc2      = 0x%08h (ky vong pc + branch_offset = 0x%08h)\n",
      "  => TO HOP NAY TAI HIEN DUOC o muc module. bpu_flush=1 von gia dinh 'backstop\n",
      "     DA chuyen huong dung o F+1'; khi backstop khong kich hoat, chuyen huong tai\n",
      "     execute thuong can HAI bong bong. Can doi chieu RTL loi de dong R3.\n",
      "=============================================================="},
      oB[2].pred_was_hit, oB[2].predicted_taken, oB[2].bpu_flush, oB[2].bpu_nxpc2_valid, oB[2].bpu_nxpc2, expB));
    chk(oB[2].bpu_flush === 2'd1, $sformatf("TH B: bpu_flush=%0d, ky vong 1 (!pred_was_hit va taken=1)", oB[2].bpu_flush));
    chk(oB[2].bpu_nxpc2_valid === 1'b1, $sformatf("TH B: corr_valid=%0d, ky vong 1", oB[2].bpu_nxpc2_valid));
    chk(oB[2].bpu_nxpc2 === expB, $sformatf("TH B: corr_nxpc2=0x%08h, ky vong pc+branch_offset=0x%08h", oB[2].bpu_nxpc2, expB));
  endtask
endclass : corr_flush_decoupling_test
