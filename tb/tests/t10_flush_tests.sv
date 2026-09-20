//------------------------------------------------------------------------------
// FILE: tests/t10_flush_tests.sv -- Nhom 10: Flush Logic
//   10.1 flush_truth_table
//   10.2 flush_uses_carry_not_pc
//------------------------------------------------------------------------------


//==============================================================================
// 10.1 flush_truth_table
//
// Sheet -- Flow: voi is_branch=0 quet moi trang thai carry-down; voi is_branch=1
//   day nhanh qua du ba tang cho tung to hop (pred_was_hit, predicted_taken,
//   branch_taken); trong nhanh BTB miss doi them btb_valid_pc tai execute.
// Sheet -- Pass: is_branch=0 -> 0. pred_was_hit=0: taken=1 cho 1, taken=0 cho 2,
//   khong phu thuoc btb_valid_pc. pred_was_hit=1: predT&actT -> 0 (KHONG bong
//   bong); predT&actNT -> 2; predNT&actT -> 2; predNT&actNT -> 0.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class flush_truth_table_test extends bpu_scene_base;
  `bpu_test_utils(flush_truth_table_test, "10.1")

  string tbl;

  // Dung mot o cua bang chan tri:
  //   hit=0 -> nxpc2 = UT ; hit=1 -> nxpc2 = TK (du doan RE) hoac NT (KHONG RE)
  //   predT=1 khi hit=0 : lay tu backstop -> opcode BCC + pc chua gap
  //   predT=0           : opcode ADDI -> d_valid=0 bat ke trang thai BTB cua pc
  local task automatic run_cell(bit hit, bit predT, bit actT, bit [31:0] pc_use, bit is_br,
                                output bpu_pipe_obs_t o[4]);
    bit [31:0] nx2 = !hit ? ADDR_UT : (predT ? ADDR_TK : ADDR_NT);
    bit [6:0]  opc = (!hit && predT) ? OPC_BR : OPC_NOP;
    pipe_probe(.pc(pc_use), .nxpc2(nx2), .taken(actT), .opc(opc), .is_branch(is_br), .o(o));
  endtask

  local task automatic do_cell(bit hit, bit predT, bit actT, bit [31:0] pc_use,
                               bit [1:0] exp_flush, string lbl);
    bpu_pipe_obs_t o[4];
    run_cell(hit, predT, actT, pc_use, 1'b1, o);
    assert_cell(lbl, o[2], .exp_hit(hit), .exp_predT(predT));
    chk(o[2].bpu_flush === exp_flush, $sformatf("%s: bpu_flush=%0d, ky vong %0d", lbl, o[2].bpu_flush, exp_flush));
    tbl = {tbl, $sformatf("  |   %0d   |   %0d   |  %0d   |   %0d   | %s\n", hit, predT, actT, o[2].bpu_flush, lbl)};
  endtask

  virtual task test_body();
    bpu_pipe_obs_t o[4];
    setup_addresses();
    tbl = "";

    //---- A: is_branch = 0 -> bpu_flush = 0 trong MOI trang thai carry-down --
    phase_of("A_no_branch_always_zero");
    run_cell(1'b1, 1'b1, 1'b1, ADDR_TK, 1'b0, o);
    chk(o[2].bpu_flush === 2'd0, $sformatf("is_branch=0 voi carry(1,1): bpu_flush=%0d, ky vong 0", o[2].bpu_flush));
    run_cell(1'b0, 1'b1, 1'b0, 32'h0000_0450, 1'b0, o);
    chk(o[2].bpu_flush === 2'd0, $sformatf("is_branch=0 voi carry(0,1): bpu_flush=%0d, ky vong 0", o[2].bpu_flush));
    run_cell(1'b1, 1'b0, 1'b1, ADDR_NT, 1'b0, o);
    chk(o[2].bpu_flush === 2'd0, $sformatf("is_branch=0 voi carry(1,0): bpu_flush=%0d, ky vong 0", o[2].bpu_flush));

    //---- B: nhanh BTB MISS (pred_was_hit = 0) ------------------------------
    phase_of("B_btb_miss_rows");
    do_cell(1'b0, 1'b0, 1'b0, 32'h0000_0460, 2'd2, "hit=0 predNT actNT");
    do_cell(1'b0, 1'b0, 1'b1, 32'h0000_0470, 2'd1, "hit=0 predNT actT ");
    do_cell(1'b0, 1'b1, 1'b0, 32'h0000_0480, 2'd2, "hit=0 predT  actNT");
    do_cell(1'b0, 1'b1, 1'b1, 32'h0000_0490, 2'd1, "hit=0 predT  actT ");

    //---- C: btb_valid_pc KHONG anh huong den flush -------------------------
    // Cung o (hit=0, predNT, actNT) hai lan: pc CHUA gap roi pc DA gap.
    phase_of("C_btb_valid_pc_has_no_effect");
    chk(bd.read_btb_valid(bpu_idx(32'h0000_04A0)) === 1'b0, "chuan bi: pc=0x4A0 phai chua duoc ghi");
    run_cell(1'b0, 1'b0, 1'b0, 32'h0000_04A0, 1'b1, o);
    chk(o[2].bpu_flush === 2'd2, $sformatf("btb_valid_pc=0: bpu_flush=%0d, ky vong 2", o[2].bpu_flush));
    h.idle(1);   // cho lenh ghi BTB cua canh len F+2 dap xuong roi moi doc
    chk(bd.read_btb_valid(bpu_idx(32'h0000_04A0)) === 1'b1, "sau lan mot: pc=0x4A0 phai da duoc ghi");
    run_cell(1'b0, 1'b0, 1'b0, 32'h0000_04A0, 1'b1, o);
    chk(o[2].bpu_flush === 2'd2, $sformatf("btb_valid_pc=1: bpu_flush=%0d, ky vong VAN 2 (khong phu thuoc btb_valid_pc)", o[2].bpu_flush));

    //---- D: nhanh BTB HIT (pred_was_hit = 1) -------------------------------
    phase_of("D_btb_hit_rows");
    refresh_nt();
    do_cell(1'b1, 1'b0, 1'b0, ADDR_NT, 2'd0, "hit=1 predNT actNT");
    do_cell(1'b1, 1'b0, 1'b1, ADDR_NT, 2'd2, "hit=1 predNT actT ");
    refresh_tk();
    do_cell(1'b1, 1'b1, 1'b0, ADDR_TK, 2'd2, "hit=1 predT  actNT");
    refresh_tk();   // hang tren lai TK voi taken=0 -> phai huan luyen lai
    do_cell(1'b1, 1'b1, 1'b1, ADDR_TK, 2'd0, "hit=1 predT  actT ");

    note({"\n=========== BANG CHAN TRI bpu_flush (is_branch = 1) ===========\n",
          "  | hit | predT | actT | flush | o\n",
          "  |-----|-------|------|-------|------------------\n", tbl,
          "  O quan trong nhat: hit=1, predT=1, actT=1 -> flush = 0.\n",
          "  Ban decode cho 1 bong bong o cung tinh huong; hybrid cho 0.\n",
          "==============================================================="});
  endtask
endclass : flush_truth_table_test


//==============================================================================
// 10.2 flush_uses_carry_not_pc
//
// Sheet -- Flow: btb_valid_nxpc2=0 tai F nhung btb_valid_pc=1 tai F+2 (entry
//   duoc ghi boi mot nhanh TRUNG CHI MUC xen vao giua); quan sat bpu_flush.
// Sheet -- Pass: bpu_flush theo nhanh BTB MISS (taken -> 1), KHONG theo btb_valid_pc.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class flush_uses_carry_not_pc_test extends bpu_scene_base;
  `bpu_test_utils(flush_uses_carry_not_pc_test, "10.2")

  localparam bit [31:0] X_PC    = 32'h0000_04B0;
  localparam bit [31:0] X_ALIAS = 32'h0000_14B0;   // cung chi muc voi X_PC

  virtual task test_body();
    bpu_pipe_obs_t o;
    int base, xidx = bpu_idx(X_PC);
    setup_addresses();

    phase_of("A_alias_writes_entry_between_F_and_Fplus2");
    chk(xidx == bpu_idx(X_ALIAS), $sformatf("chuan bi: X_PC va X_ALIAS phai TRUNG chi muc (%0d vs %0d)", xidx, bpu_idx(X_ALIAS)));
    chk(bd.read_btb_valid(xidx) === 1'b0, $sformatf("chuan bi: btb_valid[%0d] phai = 0 truoc phep do", xidx));
    h.idle(4);
    base = h.num_cycles();
    // F   : X vao FETCH voi nxpc2 = X_PC -> btb_valid_nxpc2 = 0; opcode ADDI -> predicted_taken = 0
    h.push_branch(.pc(X_PC), .taken(1'b1), .offset(32'h40), .opcode(OPC_NOP), .ovr_nxpc2(1'b1), .nxpc2(X_PC));
    // F+1 : nhanh TRUNG CHI MUC thuc thi ngay -> ghi btb[xidx] hop le
    h.push_branch(.pc(X_ALIAS), .taken(1'b1), .offset(32'h40), .opcode(OPC_NOP), .ovr_nxpc2(1'b1), .nxpc2(ADDR_UT), .is_branch(1'b1));
    h.drain();
    o = h.obs_at_cycle(base + 2);       // chinh chu ky F+2 cua nhanh X
    note($sformatf({
      "\n=== flush lay tu CARRY-DOWN chu khong tu btb_valid_pc ===\n",
      "  Tai F   : btb_valid_nxpc2 = 0 (entry chua duoc ghi)\n",
      "  Tai F+2 : btb_valid_pc    = %0d (nhanh trung chi muc da ghi xen vao giua)\n",
      "            pred_was_hit    = %0d (mang xuong tu F -> phai la 0)\n",
      "            branch_taken    = 1\n",
      "            bpu_flush       = %0d (ky vong 1 = nhanh BTB MISS + re)\n",
      "  Neu flush dung btb_valid_pc thi ket qua se la 0 (du doan dung).\n",
      "========================================================="},
      bd.read_btb_valid(xidx), o.pred_was_hit, o.bpu_flush));
    chk(bd.read_btb_valid(xidx) === 1'b1, "canh dung SAI: btb_valid_pc tai F+2 phai = 1 (nhanh trung chi muc phai ghi duoc)");
    chk(o.pred_was_hit === 1'b0, $sformatf("pred_was_hit=%0d, ky vong 0 (mang xuong tu F, luc do BTB con truot)", o.pred_was_hit));
    chk(o.bpu_flush === 2'd1, $sformatf("bpu_flush=%0d, ky vong 1 -- flush phai theo pred_was_hit, KHONG theo btb_valid_pc", o.bpu_flush));
  endtask
endclass : flush_uses_carry_not_pc_test
