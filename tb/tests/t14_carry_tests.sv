//------------------------------------------------------------------------------
// FILE: tests/t14_carry_tests.sv -- Nhom 14: Carry-down pipeline
//   14.1 carry_depth_and_merge
//   14.2 carry_paths_and_gating_scope
//   14.3 carry_across_flush        (DIEU TRA DesignNotes R2)
//   14.4 carry_back_to_back
//
// CONG THUC THAM CHIEU (bpu_ctrl.v):
//     predic_taken_delay_1 <= f_valid
//     predic_taken_delay_2 <= predic_taken_delay_1 | d_valid
//   => predicted_taken tai F+2 = f_valid(F) | d_valid(F+1)
//   Ba duong con lai (btb_hit, local, global) chi dich thuan, KHONG co phep hop
//   va KHONG qua fetch_ready.
//------------------------------------------------------------------------------


//==============================================================================
// 14.1 carry_depth_and_merge
//
// Sheet -- Flow: phat mot xung quyet dinh duy nhat tai F va quan sat
//   predicted_taken cung pred_was_hit tai F..F+3; roi ba kich ban: chi f_valid
//   tai F, chi d_valid tai F+1, ca hai.
// Sheet -- Pass: quyet dinh xuat hien dung tai F+2; sau reset tam thanh ghi = 0;
//   predicted_taken = 1 tai F+2 trong ca ba kich ban (d_valid lay tai F+1).
// RTL Ref: bpu_ctrl.v
//==============================================================================
class carry_depth_and_merge_test extends bpu_scene_base;
  `bpu_test_utils(carry_depth_and_merge_test, "14.1")

  virtual task test_body();
    bpu_pipe_obs_t o[4];

    //---- A: sau reset, ca TAM thanh ghi carry-down = 0 ---------------------
    phase_of("A_all_eight_zero_after_reset");
    check_carry_zero("sau reset");
    train_predict_taken(32'h0000_0100, 24);   // A = 0x100 -> BTB hit + du doan RE

    //---- B: do sau DUNG hai chu ky -----------------------------------------
    phase_of("B_depth_exactly_two");
    pipe_probe(.pc(32'h0000_0100), .nxpc2(32'h0000_0100), .taken(1'b1), .opc(OPC_BR), .o(o));
    foreach (o[k]) show_obs($sformatf("do sau T+%0d", k), o[k]);
    chk(o[0].predicted_taken === 1'b0, "T  : predicted_taken=1 -- duong ong chua sach truoc phep do");
    chk(o[1].predicted_taken === 1'b0, "T+1: predicted_taken=1 -- do sau chi MOT chu ky, SAI");
    chk(o[2].predicted_taken === 1'b1, "T+2: predicted_taken=0 -- quyet dinh khong toi dung chu ky");
    chk(o[3].predicted_taken === 1'b0, "T+3: predicted_taken van=1 -- quyet dinh khong roi di");
    chk(o[2].pred_was_hit    === 1'b1, "T+2: pred_was_hit=0 du BTB trung tai nxpc2 luc T");
    chk(o[1].pred_was_hit    === 1'b0, "T+1: pred_was_hit=1 -- duong BTB cung phai tre 2 chu ky");

    //---- C: CHI f_valid tai F (nxpc2 = 0x100 da huan luyen; tai F+1 BTB hop le -> d=0)
    phase_of("C_merge_f_only");
    pipe_probe(.pc(32'h0000_0100), .nxpc2(32'h0000_0100), .taken(1'b1), .opc(OPC_BR), .o(o));
    show_obs("chi f_valid", o[2]);
    chk(o[2].predicted_taken === 1'b1, "chi f_valid tai F: predicted_taken tai F+2 phai = 1");

    //---- D: CHI d_valid tai F+1 (pc = 0x900 chua gap, opcode BCC tai decode) --
    // Neu RTL lay d_valid tai F (thay vi F+1) thi predicted_taken se = 0 -> fail.
    phase_of("D_merge_d_only");
    chk(bd.read_btb_valid(576) === 1'b0, "chuan bi: btb_valid[576] (pc=0x900) phai = 0");
    pipe_probe(.pc(32'h0000_0900), .nxpc2(32'h0000_0900), .taken(1'b1), .opc(OPC_BR), .o(o));
    show_obs("chi d_valid", o[2]);
    chk(o[0].predicted_taken === 1'b0, "F  : f_valid phai = 0 cho dia chi chua huan luyen");
    chk(o[2].predicted_taken === 1'b1, "chi d_valid tai F+1: predicted_taken tai F+2 phai = 1 (phep hop lay d o F+1)");
    chk(o[2].pred_was_hit    === 1'b0, "chi d_valid: pred_was_hit phai = 0 (BTB truot tai nxpc2 luc F)");

    //---- E: CA HAI cung tich cuc (pc = 0xA00 chua gap -> d=1; nxpc2 = 0x100 -> f=1)
    phase_of("E_merge_both");
    chk(bd.read_btb_valid(640) === 1'b0, "chuan bi: btb_valid[640] (pc=0xA00) phai = 0");
    pipe_probe(.pc(32'h0000_0A00), .nxpc2(32'h0000_0100), .taken(1'b1), .opc(OPC_BR), .o(o));
    show_obs("ca f va d", o[2]);
    chk(o[2].predicted_taken === 1'b1, "ca hai: predicted_taken tai F+2 phai = 1");
    chk(o[2].pred_was_hit    === 1'b1, "ca hai: pred_was_hit phai = 1 (BTB trung tai nxpc2 = 0x100)");
  endtask
endclass : carry_depth_and_merge_test


//==============================================================================
// 14.2 carry_paths_and_gating_scope
//
// Sheet -- Flow: btb_valid_nxpc2=1 kem du doan khong re (f_valid=0) tai F; du
//   bon to hop (local[1], global[1]) tai F; lap lai voi flush_in=2 tai F trong
//   khi BTB trung va du doan re, roi cap branch_taken=1 tai F+2.
// Sheet -- Pass: pred_was_hit=1 tai F+2 du predicted_taken=0; local_carry va
//   global_carry khop gia tri tai F va quyet dinh huong cap nhat bo chon. Voi
//   flush_in=2 tai F: predicted_taken=0 (f_valid bi chan) nhung pred_was_hit=1
//   (KHONG bi chan) -> mispredict, bpu_flush=2, corr_nxpc2 = btb_target_pc (N1).
// RTL Ref: bpu_ctrl.v
//
// PHU THUOC CONG CU: chi chay duoc duoi Xcelium (force phan tu mang khong goi
// ten bi Questa tu choi, vsim-16133).
//==============================================================================
class carry_paths_and_gating_scope_test extends bpu_scene_base;
  `bpu_test_utils(carry_paths_and_gating_scope_test, "14.2")

  // Mot nhanh tai A voi nxpc2 = A sau khi dung canh; tra ve quan sat tai F+2.
  local task automatic run_scene(bit loc, bit glb, bit taken, bit [1:0] fl_f, output bpu_pipe_obs_t o);
    carry_set_scene(loc, glb);
    h.idle(4);
    h.push_branch(.pc(CARRY_A_PC), .taken(taken), .offset(32'h40), .flush_in(fl_f),
                  .ovr_nxpc2(1'b1), .nxpc2(CARRY_A_PC));
    h.drain();
    o = h.obs_of(h.last_id);
  endtask

  virtual task test_body();
    bpu_pipe_obs_t o;
    bit [1:0] ch_before, ch_after;
    scoreboard_not_applicable("phai ep local_pht/global_pht/choice/GHR/BTB de dat DOC LAP hai bit du doan local va global tai nxpc2");

    //---- A: duong BTB doc lap voi duong quyet dinh ---------------------------
    // btb_valid_nxpc2 = 1 nhung du doan KHONG re -> f_valid = 0: pred_was_hit = 1
    // trong khi predicted_taken = 0.
    phase_of("A_btb_path_independent_of_decision");
    run_scene(1'b0, 1'b0, 1'b0, 2'd0, o);
    show_obs("btb path", o);
    chk(o.pred_was_hit    === 1'b1, "pred_was_hit = 0 -- duong BTB phai mang xuong DU khong co chuyen huong");
    chk(o.predicted_taken === 1'b0, "predicted_taken = 1 -- du doan la KHONG re nen f_valid phai = 0");
    carry_clear_scene();

    //---- B: du BON to hop (local[1], global[1]) -----------------------------
    // branch_taken = 1 -> local dung khi L=1, global dung khi G=1.
    // Lenh ghi choice roi vao canh len cua F+2; helper tra ve ngay tai canh do
    // nen phai di them mot chu ky roi moi doc gia tri moi.
    phase_of("B_four_local_global_combos");
    for (int combo = 0; combo < 4; combo++) begin
      bit L = combo[1];  bit G = combo[0];
      carry_set_scene(L, G);
      h.idle(4);
      ch_before = bd.read_choice(CARRY_A_IDX);
      h.push_branch(.pc(CARRY_A_PC), .taken(1'b1), .offset(32'h40), .ovr_nxpc2(1'b1), .nxpc2(CARRY_A_PC));
      h.drain();
      o = h.obs_of(h.last_id);
      h.idle(1);
      ch_after = bd.read_choice(CARRY_A_IDX);
      show_obs($sformatf("combo L=%0d G=%0d", L, G), o);
      chk(o.local_carry  === L, $sformatf("combo L=%0d G=%0d: local_carry=%0d, ky vong %0d (gia tri tai F)", L, G, o.local_carry, L));
      chk(o.global_carry === G, $sformatf("combo L=%0d G=%0d: global_carry=%0d, ky vong %0d (gia tri tai F)", L, G, o.global_carry, G));
      // Huong cap nhat bo chon: L=G -> giu ; G=1 -> tang (global dung) ; L=1 -> giam
      if (L === G)
        chk(ch_after === ch_before, $sformatf("combo L=%0d G=%0d: choice %0d->%0d, ky vong GIU (khong bat dong)", L, G, ch_before, ch_after));
      else if (G === 1'b1)
        chk(ch_after > ch_before, $sformatf("combo L=%0d G=%0d: choice %0d->%0d, ky vong TANG (global dung)", L, G, ch_before, ch_after));
      else
        chk(ch_after < ch_before, $sformatf("combo L=%0d G=%0d: choice %0d->%0d, ky vong GIAM (local dung)", L, G, ch_before, ch_after));
      carry_clear_scene();
    end

    //---- C: BAT DOI XUNG N1 -- fetch_ready chan f_valid, KHONG chan BTB -----
    // Tai F: BTB trung + du doan RE, nhung flush_in = 2 -> fetch_ready = 0.
    phase_of("C_N1_gating_asymmetry");
    run_scene(1'b1, 1'b1, 1'b1, 2'd2, o);
    show_obs("N1 flush_in=2 @F", o);
    note($sformatf({
      "\n=== BANG CHUNG N1 (bat doi xung pham vi cua fetch_ready) ===\n",
      "  Tai F   : BTB trung tai nxpc2 = 1, du doan = RE, flush_in = 2\n",
      "  Tai F+2 : predicted_taken = %0d  (f_valid BI CHAN boi fetch_ready)\n",
      "            pred_was_hit    = %0d  (btb_hit_delay KHONG bi chan)\n",
      "            branch_taken    = 1  -> mispredict\n",
      "            bpu_flush       = %0d  (ky vong 2)\n",
      "            bpu_nxpc2       = 0x%08h (ky vong btb_target_pc = 0x%08h)\n",
      "  => fetch_ready chan f_valid nhung KHONG chan ba duong mang xuong con lai:\n",
      "     predicted_taken = 'front-end co chuyen huong khong', pred_was_hit = 'co\n",
      "     thong tin BTB khong' (dung de chon DANG dia chi hieu chinh).\n",
      "============================================================"},
      o.predicted_taken, o.pred_was_hit, o.bpu_flush, o.bpu_nxpc2, CARRY_A_TGT));
    chk(o.predicted_taken === 1'b0, "N1: predicted_taken != 0 -- fetch_ready phai chan f_valid");
    chk(o.pred_was_hit    === 1'b1, "N1: pred_was_hit != 1 -- fetch_ready KHONG duoc chan duong BTB");
    chk(o.bpu_flush       === 2'd2, $sformatf("N1: bpu_flush=%0d, ky vong 2 (mispredict khi BTB trung)", o.bpu_flush));
    chk(o.bpu_nxpc2_valid === 1'b1, "N1: bpu_nxpc2_valid != 1 (phai co hieu chinh)");
    chk(o.bpu_nxpc2       === CARRY_A_TGT, $sformatf("N1: corr_nxpc2=0x%08h, ky vong btb_target_pc=0x%08h", o.bpu_nxpc2, CARRY_A_TGT));
    carry_clear_scene();
  endtask

  // Giai thich nguon goc cac lan scoreboard bao lech: muc nay ep btb_valid[64]=1
  // bang backdoor; reference khong thay nen shadow van co btb_valid=0. Hai ben
  // danh gia tang backstop khac nhau (DUT: d_valid=0 ; REF: d_valid=1).
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    note($sformatf({
      "\n=== GIAI THICH %0d LAN SCOREBOARD BAO LECH ===\n",
      "  Muc nay ep btb_valid[%0d]=1 bang backdoor; reference model khong thay\n",
      "  lenh ep nen shadow cua no van co btb_valid=0. Hai ben do danh gia tang\n",
      "  backstop khac nhau (bpu_ctrl.v): DUT cho d_valid=0, reference cho\n",
      "  d_valid=1 va bpu_nxpc2 = nxpc + branch_target_fetch.\n",
      "  Day la he qua DA BIET cua viec ep trang thai noi bo, khong phai loi DUT.\n",
      "======================================="},
      tb.module_env.scoreboard.miscompare_count, CARRY_A_IDX));
  endfunction
endclass : carry_paths_and_gating_scope_test


//==============================================================================
// 14.3 carry_across_flush        --- MUC DIEU TRA (DesignNotes R2)
//
// Sheet -- Flow: dua nhanh vao fetch tai F; flush_in=2 tai F+1 (duong ong bi xoa
//   boi mot nhanh truoc do); theo doi toi F+2.
// Sheet -- Pass: GHI NHAN -- fetch_ready chan f_valid va d_valid nhung khong chan
//   ba duong con lai. Khong phat sinh du doan sai / hieu chinh gia cho lenh da xoa.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class carry_across_flush_test extends bpu_scene_base;
  `bpu_test_utils(carry_across_flush_test, "14.3")

  virtual task test_body();
    bpu_pipe_obs_t oA[4], oB, oC;
    int base;
    train_predict_taken(32'h0000_0100, 24);      // A = 0x100 -> BTB hit + du doan RE

    //---- A: lenh VAN toi execute -- flush_in=2 chi o F+1 --------------------
    phase_of("A_flush_at_Fplus1_branch_survives");
    pipe_probe(.pc(32'h0000_0100), .nxpc2(32'h0000_0100), .taken(1'b1), .opc(OPC_BR), .fl_d(2'd2), .o(oA));
    show_obs("A: flush@F+1, song sot", oA[2]);
    chk(oA[2].predicted_taken === 1'b1, "A: predicted_taken=0 -- quyet dinh tai F bi mat du flush_in chi dat o F+1");
    chk(oA[2].pred_was_hit    === 1'b1, "A: pred_was_hit=0 -- duong BTB bi flush_in chan (khong dung theo RTL)");
    chk(oA[2].bpu_flush       === 2'd0, $sformatf("A: bpu_flush=%0d, ky vong 0 (du doan RE va thuc te RE)", oA[2].bpu_flush));

    //---- B: lenh BI XOA -- toi execute voi is_branch = 0 --------------------
    // Quyet dinh cua lenh da xoa VAN nam trong duong ong tai F+2: co sinh flush
    // hay hieu chinh gia khong?
    phase_of("B_killed_instruction_no_spurious");
    h.idle(4);
    base = h.num_cycles();
    h.push_branch(.pc(32'h0000_0100), .taken(1'b1), .offset(32'h40), .ovr_nxpc2(1'b1), .nxpc2(32'h0000_0100));   // F: f_valid = 1
    h.idle(1, 2'd2, 1'b0);                                                                                     // F+1: flush_in = 2
    h.push_branch(.pc(NEU_PC), .taken(1'b0), .offset(32'h0), .is_branch(1'b0));                                // F+2: is_branch = 0
    h.idle(2);
    oB = h.obs_at_cycle(base + 2);
    show_obs("B: lenh bi xoa @F+2", oB);
    chk(oB.predicted_taken === 1'b1, "B: predicted_taken=0 -- duong ong PHAI van mang quyet dinh cu (RTL khong xoa theo flush)");
    chk(oB.bpu_flush       === 2'd0, $sformatf("B: bpu_flush=%0d, ky vong 0 -- is_branch=0 phai ep flush=0 (bpu_ctrl.v)", oB.bpu_flush));

    //---- C: nhanh KE TIEP co bi lay nham quyet dinh cu khong? ---------------
    // W (0xB00) duoc huan luyen truoc de btb_valid=1 -> d_valid cua chinh W = 0.
    phase_of("C_next_branch_not_contaminated");
    drive_branch(32'h0000_0B00, 1'b1, 32'h40);
    chk(bd.read_btb_valid(704) === 1'b1, "chuan bi: btb_valid[704] (pc=0xB00) phai = 1");
    h.idle(4);
    h.push_branch(.pc(32'h0000_0100), .taken(1'b1), .offset(32'h40), .ovr_nxpc2(1'b1), .nxpc2(32'h0000_0100));   // F  : f_valid = 1
    h.push_branch(.pc(32'h0000_0B00), .taken(1'b0), .offset(32'h40), .flush_in(2'd2),                            // F+1: chan ca f va d cua W
                  .ovr_nxpc2(1'b1), .nxpc2(NEU_NXPC2));
    h.drain();
    oC = h.obs_of(h.last_id);                                 // W tai F+3
    show_obs("C: nhanh ke tiep W", oC);
    chk(oC.predicted_taken === 1'b0, "C: W thay predicted_taken=1 -- XUYEN NHIEM: quyet dinh cua lenh truoc dinh lai");

    note($sformatf({
      "\n=== DIEU TRA DesignNotes R2: carry-down khi co flush ===\n",
      "  Quan sat 1: flush_in KHONG xoa duong ong. Pha A cho predicted_taken=%0d,\n",
      "              pred_was_hit=%0d tai F+2 du flush_in=2 tai F+1 (chi rst_n xoa, halt dong bang).\n",
      "  Quan sat 2: lenh DA BI XOA (is_branch=0 tai execute): bpu_flush=%0d va KHONG co\n",
      "              hieu chinh -- quyet dinh con sot lai la VO HAI.\n",
      "  Quan sat 3: nhanh ke tiep W thay predicted_taken=%0d, dung bang quyet dinh fetch cua\n",
      "              CHINH NO. Duong ong mang tinh VI TRI.\n",
      "  KET LUAN  : o muc module KHONG tai hien duoc du doan sai / hieu chinh gia cho lenh\n",
      "              da bi xoa. Rui ro con lai thuoc muc TICH HOP (lenh da xoa van toi execute\n",
      "              voi is_branch=1). Can doi chieu voi RTL loi de dong R2.\n",
      "======================================================="},
      oA[2].predicted_taken, oA[2].pred_was_hit, oB.bpu_flush, oC.predicted_taken));
  endtask
endclass : carry_across_flush_test


//==============================================================================
// 14.4 carry_back_to_back
//
// Sheet -- Flow: chuoi nhanh o cac chu ky lien tiep, moi nhanh co quyet dinh
//   fetch khac nhau (xen ke f_valid=1 va f_valid=0).
// Sheet -- Pass: moi nhanh toi execute kem DUNG quyet dinh cua chinh no; khong
//   xuyen nhieu giua hai tang cua duong ong.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class carry_back_to_back_test extends bpu_scene_base;
  `bpu_test_utils(carry_back_to_back_test, "14.4")

  localparam int N = 8;

  virtual task test_body();
    bpu_pipe_obs_t o;
    int ids[N], n_wrong = 0, d;
    bit exp_pt;
    bit [31:0] pc_i;

    //---- Chuan bi: A = 0x100 -> f_valid=1; P_i huan luyen NHE de btb_valid=1
    // (d_valid cua chinh no = 0 -> predicted_taken chi phu thuoc f_valid cua no)
    phase_of("prep_train");
    train_predict_taken(32'h0000_0100, 24);
    for (int i = 0; i < N; i++) begin
      pc_i = 32'h0000_0200 + (i * 32'h0000_0100);
      drive_branch(pc_i, 1'b1, 32'h40);
      chk(bd.read_btb_valid(bpu_idx(pc_i)) === 1'b1, $sformatf("chuan bi: btb_valid cho pc=0x%08h phai = 1", pc_i));
    end

    //---- A: N nhanh o cac chu ky KE NHAU, f_valid xen ke --------------------
    // i chan -> nxpc2 = 0x100 (du doan RE) -> f_valid = 1 ; i le -> nxpc2 = 0xFF8 -> f_valid = 0
    phase_of("A_alternating_f_valid_back_to_back");
    h.idle(4);
    for (int i = 0; i < N; i++) begin
      pc_i = 32'h0000_0200 + (i * 32'h0000_0100);
      h.push_branch(.pc(pc_i), .taken(1'b1), .offset(32'h40), .ovr_nxpc2(1'b1),
                    .nxpc2((i % 2 == 0) ? 32'h0000_0100 : NEU_NXPC2));
      ids[i] = h.last_id;
    end
    h.drain();
    for (int i = 0; i < N; i++) begin
      o      = h.obs_of(ids[i]);
      exp_pt = (i % 2 == 0);
      show_obs($sformatf("nhanh #%0d (ky vong predT=%0d)", i, exp_pt), o);
      if (o.predicted_taken !== exp_pt) begin
        n_wrong++;
        chk(1'b0, $sformatf("nhanh #%0d (pc=0x%08h): predicted_taken=%0d, ky vong %0d -- XUYEN NHIEM giua cac tang", i, o.pc, o.predicted_taken, exp_pt));
      end
      chk(o.pred_was_hit === exp_pt, $sformatf("nhanh #%0d: pred_was_hit=%0d, ky vong %0d (duong BTB cung phai theo dung nhanh)", i, o.pred_was_hit, exp_pt));
    end

    //---- B: cac nhanh THAT SU o chu ky ke nhau ------------------------------
    phase_of("B_cycles_are_adjacent");
    for (int i = 1; i < N; i++) begin
      d = h.obs_of(ids[i]).cycle - h.obs_of(ids[i-1]).cycle;
      chk(d === 1, $sformatf("nhanh #%0d va #%0d cach nhau %0d chu ky, ky vong 1 (back_to_back khong hoat dong)", i-1, i, d));
    end
    note($sformatf("back-to-back: %0d nhanh o %0d chu ky lien tiep, sai quyet dinh = %0d",
                   N, h.obs_of(ids[N-1]).cycle - h.obs_of(ids[0]).cycle + 1, n_wrong));
  endtask
endclass : carry_back_to_back_test
