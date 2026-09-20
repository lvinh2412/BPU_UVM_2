//------------------------------------------------------------------------------
// FILE: tests/t11_redirect_tests.sv -- Nhom 11: Tang chuyen huong
//   11.1 redirect_fetch_tier
//   11.2 redirect_backstop
//   11.3 redirect_priority_matrix
//------------------------------------------------------------------------------


//==============================================================================
// 11.1 redirect_fetch_tier
// Sheet -- Flow: nap BTB tai nxpc2_index va dua bo du doan ve trang thai du doan
//   re; quet nhieu dia chi dich; theo nhanh toi tang execute.
// Sheet -- Pass: bpu_nxpc2 = btb_target_nxpc2 va bpu_nxpc2_valid=1; nhanh nay
//   ve sau cho bpu_flush=0 neu du doan dung, tuc KHONG ton bong bong.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class redirect_fetch_tier_test extends bpu_scene_base;
  `bpu_test_utils(redirect_fetch_tier_test, "11.1")

  virtual task test_body();
    bpu_pipe_obs_t o[4];
    bit [31:0] offs[4] = '{32'h0000_0040, 32'h0000_0800, 32'hFFFF_FFC0, 32'h0000_0000};
    bit [31:0] exp_tgt;
    setup_addresses();

    //---- A: quet nhieu dia chi dich -- moi vong huan luyen lai TK voi offset khac
    phase_of("A_sweep_targets");
    foreach (offs[k]) begin
      repeat (4) drive_branch(ADDR_TK, 1'b1, offs[k]);   // btb_target[TK] = TK + offs
      exp_tgt = ADDR_TK + offs[k];
      chk(bd.read_btb_target(bpu_idx(ADDR_TK)) === exp_tgt,
          $sformatf("chuan bi offset 0x%08h: btb_target[TK]=0x%08h, ky vong 0x%08h", offs[k], bd.read_btb_target(bpu_idx(ADDR_TK)), exp_tgt));
      pipe_probe(.pc(ADDR_TK), .nxpc2(ADDR_TK), .taken(1'b1), .offset(offs[k]), .o(o));
      note($sformatf("offset=0x%08h : tai F  valid=%0d nxpc2=0x%08h (ky vong btb_target_nxpc2=0x%08h)",
                     offs[k], o[0].bpu_nxpc2_valid, o[0].bpu_nxpc2, exp_tgt));
      chk(o[0].bpu_nxpc2_valid === 1'b1, $sformatf("offset 0x%08h: bpu_nxpc2_valid tai F != 1", offs[k]));
      chk(o[0].bpu_nxpc2 === exp_tgt, $sformatf("offset 0x%08h: bpu_nxpc2=0x%08h tai F, ky vong 0x%08h (btb_target_nxpc2)", offs[k], o[0].bpu_nxpc2, exp_tgt));
    end

    //---- B: du doan dung -> KHONG ton bong bong -----------------------------
    phase_of("B_correct_predict_zero_bubble");
    pipe_probe(.pc(ADDR_TK), .nxpc2(ADDR_TK), .taken(1'b1), .o(o));
    assert_cell("du doan dung", o[2], .exp_hit(1'b1), .exp_predT(1'b1));
    note($sformatf({
      "\n=== LOI ICH HYBRID: tang fetch du doan dung -> KHONG bong bong ===\n",
      "  pred_was_hit=1, predicted_taken=1, branch_taken=1 -> bpu_flush=%0d\n",
      "  (ban decode cho 1 bong bong o cung tinh huong nay)\n",
      "=================================================================="}, o[2].bpu_flush));
    chk(o[2].bpu_flush === 2'd0, $sformatf("du doan dung: bpu_flush=%0d, ky vong 0 (khong bong bong)", o[2].bpu_flush));
  endtask
endclass : redirect_fetch_tier_test


//==============================================================================
// 11.2 redirect_backstop
// Sheet -- Flow: BTB miss tai nxpc voi fetch_opcode=BCC; quet branch_target_fetch
//   duong, am va bang 0.
// Sheet -- Pass: bpu_nxpc2 = nxpc + branch_target_fetch trong ca ba truong hop
//   va bpu_nxpc2_valid=1; chi phi MOT bong bong khi nhanh thuc su re.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class redirect_backstop_test extends bpu_scene_base;
  `bpu_test_utils(redirect_backstop_test, "11.2")

  virtual task test_body();
    bpu_pipe_obs_t o[4];
    bit [31:0] btfs[3] = '{32'h0000_0040, 32'hFFFF_FFC0, 32'h0000_0000};
    bit [31:0] pcs[3]  = '{32'h0000_0400, 32'h0000_0410, 32'h0000_0420};   // moi pc CHUA tung gap
    bit [31:0] exp;
    setup_addresses();

    phase_of("A_sweep_btf_sign");
    foreach (btfs[k]) begin
      chk(bd.read_btb_valid(bpu_idx(pcs[k])) === 1'b0, $sformatf("chuan bi: btb_valid cho pc=0x%08h phai = 0", pcs[k]));
      pipe_probe(.pc(pcs[k]), .nxpc2(ADDR_UT), .taken(1'b1), .opc(OPC_BR), .btf(btfs[k]), .o(o));
      exp = pcs[k] + btfs[k];        // d_nxpc2 = nxpc + branch_target_fetch
      note($sformatf("btf=0x%08h : tai F+1 valid=%0d nxpc2=0x%08h (ky vong nxpc+btf=0x%08h)", btfs[k], o[1].bpu_nxpc2_valid, o[1].bpu_nxpc2, exp));
      chk(o[1].bpu_nxpc2_valid === 1'b1, $sformatf("btf=0x%08h: bpu_nxpc2_valid tai F+1 != 1", btfs[k]));
      chk(o[1].bpu_nxpc2 === exp, $sformatf("btf=0x%08h: bpu_nxpc2=0x%08h, ky vong 0x%08h (nxpc + btf)", btfs[k], o[1].bpu_nxpc2, exp));
      chk(o[2].bpu_flush === 2'd1, $sformatf("btf=0x%08h: bpu_flush=%0d tai F+2, ky vong 1 (BTB miss + re)", btfs[k], o[2].bpu_flush));
    end
  endtask
endclass : redirect_backstop_test


//==============================================================================
// 11.3 redirect_priority_matrix
// Sheet -- Flow: bon to hop cua (d_valid, f_valid) voi hai dich phan biet. O
//   (0,0) dung bang BTB TRUNG tai nxpc2 kem du doan KHONG RE.
// Sheet -- Pass: (1,1) va (1,0) cho bpu_nxpc2 = d_nxpc2; (0,1) cho f_nxpc2;
//   (0,0) cho bpu_nxpc2_valid=0 -- hybrid da bo han duong pc+4 cua S3.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class redirect_priority_matrix_test extends bpu_scene_base;
  `bpu_test_utils(redirect_priority_matrix_test, "11.3")

  localparam bit [31:0] PC_D_NEW = 32'h0000_0430;   // pc chua gap -> d_valid duoc
  localparam bit [31:0] BTF_D    = 32'h0000_0044;

  // Dung MOT chu ky co (d_valid, f_valid) theo y: B1 day vao truoc (o DECODE),
  // B2 day vao sau (o FETCH); EXECUTE trong (is_branch=0) nen corr_valid = 0.
  local task automatic run_cell(bit want_d, bit want_f, output bpu_pipe_obs_t o);
    int base;
    h.idle(4);
    h.push_branch(.pc(want_d ? PC_D_NEW : ADDR_TK), .taken(1'b0), .offset(32'h40), .opcode(OPC_BR),
                  .btf(BTF_D), .is_branch(1'b0), .ovr_nxpc2(1'b1), .nxpc2(ADDR_UT));
    base = h.num_cycles();
    h.push_branch(.pc(32'h0000_0440), .taken(1'b0), .offset(32'h40), .opcode(OPC_NOP),
                  .is_branch(1'b0), .ovr_nxpc2(1'b1), .nxpc2(want_f ? ADDR_TK : ADDR_NT));
    o = h.obs_at_cycle(base);
    h.drain();
  endtask

  local task automatic do_cell(string ph, bit d, bit f, bit exp_v, bit [31:0] exp, string why);
    bpu_pipe_obs_t o;
    phase_of(ph);
    run_cell(d, f, o);
    show_obs($sformatf("d=%0d f=%0d", d, f), o);
    chk(o.bpu_nxpc2_valid === exp_v, $sformatf("(%0d,%0d): valid=%0d, ky vong %0d", d, f, o.bpu_nxpc2_valid, exp_v));
    chk(o.bpu_nxpc2 === exp, $sformatf("(%0d,%0d): nxpc2=0x%08h, ky vong 0x%08h (%s)", d, f, o.bpu_nxpc2, exp, why));
  endtask

  virtual task test_body();
    bit [31:0] d_tgt, f_tgt;
    setup_addresses();
    d_tgt = PC_D_NEW + BTF_D;                          // nxpc + btf
    f_tgt = bd.read_btb_target(bpu_idx(ADDR_TK));      // btb_target_nxpc2
    do_cell("A_d1_f1_backstop_wins", 1'b1, 1'b1, 1'b1, d_tgt, "d_nxpc2: backstop uu tien hon fetch");
    do_cell("B_d1_f0_backstop",      1'b1, 1'b0, 1'b1, d_tgt, "d_nxpc2");
    do_cell("C_d0_f1_fetch",         1'b0, 1'b1, 1'b1, f_tgt, "f_nxpc2 = btb_target_nxpc2");
    do_cell("D_d0_f0_no_redirect",   1'b0, 1'b0, 1'b0, 32'd0, "hybrid phai BO duong chuyen huong pc+4 (S3 cu)");
  endtask
endclass : redirect_priority_matrix_test
