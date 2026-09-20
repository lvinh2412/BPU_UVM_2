//------------------------------------------------------------------------------
// FILE: tests/t01_reset_tests.sv -- Nhom 1: Reset & Init
//   1.1 rst_state_and_async
//   1.2 rst_outputs_and_recovery
//------------------------------------------------------------------------------


//==============================================================================
// 1.1 rst_state_and_async
//
// Sheet -- Flow: Pha A assert rst_n o nhieu thoi diem (khi nghi, giua luc dang
//   ghi, khi halt=1); doc lai toan bo bang bang backdoor. Pha B assert rst_n
//   giua chu ky, khong trung canh len clk; quan sat thoi diem ve mac dinh.
// Sheet -- Pass: btb_valid=0, btb_target=0, local_bht=0 (12 bit),
//   local_pht=SNT, global_pht=SNT, choice=WNT, ghr=0, carry-down=0. Pha B:
//   trang thai ve mac dinh NGAY khi rst_n xuong thap, khong cho canh len clk.
// RTL Ref: bpu_reg.v ; bpu_ctrl.v
//==============================================================================
class rst_state_and_async_test extends bpu_scene_base;
  `bpu_test_utils(rst_state_and_async_test, "1.1")

  // Mot chu ky co is_branch=1 tai ADDR_TK -> ca sau wr_en tich cuc.
  local task automatic writing_cycle(bit halt);
    apply(.pc(ADDR_TK), .nxpc(ADDR_TK + 4), .nxpc2(ADDR_TK), .opcode(OPC_BR),
          .btf(32'h40), .halt(halt), .is_branch(1'b1), .taken(1'b1), .offset(32'h80));
  endtask

  // Nha reset sau mot lan ep giua chung, don duong ong, kiem lai.
  local task automatic release_and_check(string tag);
    bd.release_tb_reset();
    apply_idle(4);
    bus_free();
    h.reset_pipe();
    #50ns;
    check_defaults(tag);
  endtask

  virtual task test_body();
    //---- A0: ngay sau reset dau tien ---------------------------------------
    phase_of("A0_after_power_on_reset");
    check_defaults("A0");

    //---- A1: assert rst_n khi he thong DANG NGHI ---------------------------
    phase_of("A1_reset_while_idle");
    dirty_state("A1");
    apply_idle(6);
    reset_by_force(3);
    check_defaults("A1");

    //---- A2: assert rst_n GIUA LUC DANG GHI --------------------------------
    phase_of("A2_reset_while_writing");
    bus_free();
    dirty_state("A2");
    repeat (6) writing_cycle(.halt(1'b0));
    bd.force_tb_reset(1'b1);          // danh vao giua chu ky ghi
    #0.2ns;
    chk(bd.read_tb_rst_n() === 1'b0, "A2: ep reset roi ma rst_n van = 1");
    check_defaults("A2_ngay_khi_reset_danh_vao");
    // Ngung phat lenh NGAY trong nua chu ky nay: reference model xoa shadow tai
    // canh rst_n nhung khong mo hinh "dang bi giu trong reset"; de is_branch=1
    // qua canh len ke tiep thi reference ghi con DUT thi khong -> lech gia.
    apply_now_idle();
    apply_idle(3);
    release_and_check("A2");

    //---- A3: assert rst_n khi halt = 1 -------------------------------------
    phase_of("A3_reset_while_halted");
    bus_free();
    dirty_state("A3");
    repeat (4) writing_cycle(.halt(1'b1));
    bd.force_tb_reset(1'b1);          // halt=1 KHONG duoc chan reset
    #0.2ns;
    chk(bd.read_tb_rst_n() === 1'b0, "A3: ep reset roi ma rst_n van = 1");
    check_defaults("A3_ngay_khi_reset_danh_vao");
    repeat (3) writing_cycle(.halt(1'b1));
    release_and_check("A3");
    note("A3: halt=1 khong chan duoc reset -- bpu_reg.v kiem !rst_n TRUOC khi kiem halt");

    //---- B: reset BAT DONG BO -- assert giua chu ky, doc NGAY ---------------
    phase_of("B_async_mid_cycle");
    bus_free();
    dirty_state("B");
    apply_idle(4);
    bus_free();
    @(negedge pvif.clock);
    #1ns;
    chk(pvif.clock === 1'b0, "B: khong dung duoc o giua chu ky de assert reset");
    bd.force_tb_reset(1'b1);
    #0.2ns;                            // chi de cac khoi always bat dong bo chay
    chk(bd.read_tb_rst_n() === 1'b0, $sformatf("B: ep reset roi ma rst_n = %0d, ky vong 0", bd.read_tb_rst_n()));
    check_defaults("B_async");         // moi phep doc la ham, khong ton thoi gian
    chk(pvif.clock === 1'b0,
        "B: da qua mot canh len clk truoc khi doc xong -- KHONG chung minh duoc tinh bat dong bo");
    note($sformatf({
      "\n=== 1.1 PHA B: reset BAT DONG BO ===\n",
      "  assert rst_n tai t = %0t, giua chu ky (clk dang o muc thap).\n",
      "  Toan bo sau bang, GHR va tam thanh ghi carry-down da ve mac dinh NGAY,\n",
      "  khong cho canh len clk (clk van = %0d khi doc xong).\n",
      "===================================="}, $time, pvif.clock));
    bd.release_tb_reset();
    repeat (3) @(negedge pvif.clock);
    h.reset_pipe();
    #50ns;
    check_defaults("B_after_release");
  endtask
endclass : rst_state_and_async_test


//==============================================================================
// 1.2 rst_outputs_and_recovery
//
// Sheet -- Flow: reset, giu nghi vai chu ky, phat nhanh dau tien (BTB miss tai
//   nxpc2 va nxpc, fetch_opcode=BCC). Sau do lap muoi lan chu trinh reset/nha
//   reset, moi lan phat mot nhanh ngay sau khi nha.
// Sheet -- Pass: ngay sau reset bpu_nxpc2_valid=0 va bpu_flush=0. Nhanh dau:
//   f_valid=0, d_valid=1, bpu_nxpc2 = nxpc + branch_target_fetch. Vi carry-down=0
//   nen nhanh dau sau moi lan reset khong bi so voi quyet dinh cua lan truoc.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class rst_outputs_and_recovery_test extends bpu_scene_base;
  `bpu_test_utils(rst_outputs_and_recovery_test, "1.2")

  localparam int        N_CYCLE  = 10;
  localparam bit [31:0] FIRST_PC = 32'h0000_0B00;    // idx 704, chua tung ghi
  localparam bit [31:0] BTF      = 32'h0000_0040;

  local function void chk_outputs_idle(string tag);
    chk(bd.read_bpu_nxpc2_valid() === 1'b0, $sformatf("%s: bpu_nxpc2_valid=%0d, ky vong 0", tag, bd.read_bpu_nxpc2_valid()));
    chk(bd.read_bpu_flush()       === 2'd0, $sformatf("%s: bpu_flush=%0d, ky vong 0", tag, bd.read_bpu_flush()));
  endfunction

  virtual task test_body();
    bpu_fetch_obs_t oF, oD, oX;
    int m;

    //---- A: ngo ra o trang thai nghi ngay sau reset ------------------------
    phase_of("A_outputs_idle_after_reset");
    chk_outputs_idle("A ngay sau reset");
    check_carry_zero("A");
    apply_idle(6);
    chk_outputs_idle("A sau vai chu ky nghi");

    //---- B: nhanh dau tien di theo duong backstop --------------------------
    phase_of("B_first_branch_backstop");
    first_branch_backstop(FIRST_PC, BTF, oF, oD, oX);
    note($sformatf({
      "\n=== 1.2 nhanh DAU TIEN sau reset ===\n",
      "  F   : f_valid=%0d d_valid=%0d -> bpu_nxpc2_valid=%0d\n",
      "  F+1 : f_valid=%0d d_valid=%0d -> bpu_nxpc2_valid=%0d bpu_nxpc2=0x%08h (nxpc+btf=0x%08h)\n",
      "  F+2 : pred_was_hit=%0d predicted_taken=%0d branch_taken=1 -> bpu_flush=%0d\n",
      "===================================="},
      oF.fv, oF.dv, oF.outv, oD.fv, oD.dv, oD.outv, oD.outp, FIRST_PC + BTF,
      bd.read_pred_was_hit(), bd.read_predicted_taken(), oX.fl));
    check_first_branch("B", FIRST_PC, BTF, oF, oD, oX);

    //---- C: MUOI chu trinh reset / nha reset -- DOC TRUOC, phat nhanh SAU ---
    phase_of("C_repeat_reset_x10");
    for (int k = 0; k < N_CYCLE; k++) begin
      string tag = $sformatf("C vong %0d", k);
      bus_free();
      reset_by_sequence();
      // (1) doc TRUOC khi phat bat ky nhanh nao
      chk(bd.read_ghr() === 10'd0, $sformatf("%s: ghr=0x%03h ngay sau reset, ky vong 0", tag, bd.read_ghr()));
      m = bd.count_choice_not_wnt();
      chk(m == 0, $sformatf("%s: choice con %0d o khac WNT sau reset", tag, m));
      m = bd.check_table_zero(0);
      chk(m == 0, $sformatf("%s: btb_valid con %0d o khac 0 sau reset", tag, m));
      check_carry_zero(tag);
      chk_outputs_idle({tag, " ngay sau reset"});
      // (2) khong xung nhieu: hai chu ky nghi truoc nhanh dau
      apply_idle(2);
      chk_outputs_idle({tag, " xung nhieu trong luc nghi"});
      // (3) nhanh dau sau khi nha reset phai cho DUNG ket qua nhu lan dau
      first_branch_backstop(FIRST_PC, BTF, oF, oD, oX);
      check_first_branch(tag, FIRST_PC, BTF, oF, oD, oX);
    end
    note($sformatf("C: %0d chu trinh reset/nha reset, moi lan nhanh dau deu di dung duong backstop va cho bpu_flush=1", N_CYCLE));
    bus_free();
  endtask
endclass : rst_outputs_and_recovery_test
