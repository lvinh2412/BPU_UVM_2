//------------------------------------------------------------------------------
// FILE: tests/t08_predict_tests.sv -- Nhom 8: Du doan tai tang fetch
//   8.1 predict_mux_nxpc2
//   8.2 predict_index_alignment
//
// Bo chon nam gon trong MOT dong (bpu_predictor.v):
//   predict_taken_nxpc2 = choice_data_nxpc2[1] ? global_pht_data_nxpc2[1]
//                                              : local_pht_data_nxpc2[1]
// Hai che do quan sat:
//   (1) DUONG THAT  -- observe_at() chi ep chan giao tiep, scoreboard song; cac
//       coverpoint co iff(btb_valid_nxpc2) lay mau tu shadow cua reference nen
//       CHI che do nay moi nang duoc chung.
//   (2) CUA SO BACKDOOR -- bd_set_*() ep them bang noi bo, chay voi flush_in=2
//       va is_branch=0 nen ca DUT lan reference deu cho ngo ra 0 -> khong lech.
//------------------------------------------------------------------------------


//==============================================================================
// 8.1 predict_mux_nxpc2
//
// Sheet -- Flow: ep du tam to hop cua ba bit (choice[1], local[1], global[1]);
//   voi moi nhanh chon, thay doi nxpc2 va GHR de xac nhan dung nguon; pha cuoi
//   giu nguyen ngo vao va chay 50 chu ky.
// Sheet -- Pass: predict_taken_nxpc2 dung bang chan tri; choice[1]=0 bam local,
//   =1 bam global; lich su/GHR khac cho du doan khac; ngo ra khong doi 50 chu ky.
// RTL Ref: bpu_predictor.v
//==============================================================================
class predict_mux_nxpc2_test extends bpu_scene_base;
  `bpu_test_utils(predict_mux_nxpc2_test, "8.1")

  localparam bit [31:0] ADDR_W = 32'h0000_0800;   // idx 512, dia chi la cho warm_cycle

  virtual task test_body();
    bpu_fetch_obs_t o, o2;
    bit [11:0] lidx_tk, lidx_nt;
    int        gidx_tk, gidx_nt, gidx_skew, cidx_tk, cidx_nt;
    bit [1:0]  sav_l_tk, sav_l_nt, sav_g_tk, sav_c_tk;
    bit [9:0]  sav_ghr;
    string     tbl;

    //---- A: bo chon tren DUONG THAT (khong ep gi) ---------------------------
    phase_of("A_real_path_mux");
    setup_addresses();          // TK: 24 nhanh re ; NT: 6 nhanh khong re
    // A1 -- TK: choice[1]=0 => bam LOCAL, o day local != global
    observe_at(ADDR_TK, 2'd0, o);
    show_fetch("A1 TK choice=0 -> local", ADDR_TK, o);
    assert_fetch_cell("A1 TK", o, .exp_hit(1'b1), .exp_l(1'b1), .exp_g(1'b0), .exp_c(1'b0));
    chk(o.pt === 1'b1, $sformatf("A1 TK: predict_taken_nxpc2=%0d, ky vong 1 (= local[1])", o.pt));
    // A2 -- NT: choice[1]=1 => bam GLOBAL (local == global == 0)
    observe_at(ADDR_NT, 2'd0, o);
    show_fetch("A2 NT choice=1 -> global", ADDR_NT, o);
    assert_fetch_cell("A2 NT", o, .exp_hit(1'b1), .exp_l(1'b0), .exp_g(1'b0), .exp_c(1'b1));
    chk(o.pt === 1'b0, $sformatf("A2 NT: predict_taken_nxpc2=%0d, ky vong 0 (= global[1])", o.pt));
    // A3 -- nang local_pht[0] len 1 (NT co local_bht=0 nen doc o do) trong khi
    //       global cua NT van 0 => choice[1]=1 VA local != global: phai lay global.
    bus_free();
    warm_cycle(ADDR_W);
    observe_at(ADDR_NT, 2'd0, o);
    show_fetch("A3 NT choice=1, local!=global", ADDR_NT, o);
    assert_fetch_cell("A3 NT", o, .exp_hit(1'b1), .exp_l(1'b1), .exp_g(1'b0), .exp_c(1'b1));
    chk(o.pt === 1'b0, $sformatf("A3 NT: predict_taken_nxpc2=%0d, ky vong 0 -- choice[1]=1 phai bam GLOBAL(0) chu khong phai LOCAL(1)", o.pt));
    // A4 -- TK sau vong ham: choice[1]=0 va local == global == 1
    observe_at(ADDR_TK, 2'd0, o);
    show_fetch("A4 TK choice=0, local==global", ADDR_TK, o);
    assert_fetch_cell("A4 TK", o, .exp_hit(1'b1), .exp_l(1'b1), .exp_g(1'b1), .exp_c(1'b0));
    chk(o.pt === 1'b1, $sformatf("A4 TK: predict_taken_nxpc2=%0d, ky vong 1", o.pt));
    note({"\n=== PHA A (duong that) da cham du bon diem lay mau co iff(btb_valid_nxpc2) ===\n",
          "  predict_T (A1,A4) / predict_NT (A2,A3)\n",
          "  agree     (A2,A4) / disagree   (A1,A3)\n",
          "  use_local (A1,A4) / use_global (A2,A3)\n",
          "==========================================================================="});

    //---- B: bang chan tri day du 8 to hop (cua so backdoor) -----------------
    phase_of("B_truth_table_8");
    bd_window_open();
    cidx_tk  = bpu_idx(ADDR_TK);
    cidx_nt  = bpu_idx(ADDR_NT);
    lidx_tk  = bd.read_local_bht(cidx_tk);   // chi muc local_pht doc tai nxpc2=TK
    lidx_nt  = bd.read_local_bht(cidx_nt);
    gidx_tk  = cidx_tk;                      // GHR ep ve 0 => chi muc = nxpc2_index
    gidx_nt  = cidx_nt;
    gidx_skew = cidx_tk ^ 10'h155;           // chi muc global khi GHR = 0x155
    sav_l_tk = bd.read_local_pht(lidx_tk);
    sav_l_nt = bd.read_local_pht(lidx_nt);
    sav_g_tk = bd.read_global_pht(gidx_tk);
    sav_c_tk = bd.read_choice(cidx_tk);
    sav_ghr  = bd.read_ghr();
    chk(bd.read_btb_valid(cidx_tk) === 1'b1, "chuan bi B: btb_valid[TK] phai = 1 thi moi doc duoc du doan tai nxpc2");
    chk(lidx_tk !== lidx_nt, $sformatf("chuan bi B: local_bht[TK]=0x%03h va local_bht[NT]=0x%03h phai KHAC nhau", lidx_tk, lidx_nt));
    bd_set_ghr(10'd0);
    tbl = {"\n=== 8.1 BANG CHAN TRI predict_taken_nxpc2 (bpu_predictor.v) ===\n",
           "   choice[1]  local[1]  global[1] | ky vong | do duoc | nguon\n",
           "   ------------------------------------------------------------\n"};
    for (int k = 0; k < 8; k++) begin
      bit c = k[2];  bit l = k[1];  bit g = k[0];
      bit expp = c ? g : l;
      bd_set_choice    (cidx_tk, c ? `WT : `WNT);
      bd_set_local_pht (lidx_tk, l ? `ST : `SNT);
      bd_set_global_pht(gidx_tk, g ? `ST : `SNT);
      observe_at(ADDR_TK, 2'd2, o);
      chk(o.ch[1] === c && o.lp[1] === l && o.gp[1] === g, $sformatf(
          "to hop %0d: canh dung SAI -- doc lai duoc choice=%0d local=%0d global=%0d (can %0d/%0d/%0d)", k, o.ch[1], o.lp[1], o.gp[1], c, l, g));
      chk(o.pt === expp, $sformatf("to hop (choice=%0d local=%0d global=%0d): predict_taken_nxpc2=%0d, ky vong %0d", c, l, g, o.pt, expp));
      chk(o.outv === 1'b0, $sformatf("to hop (choice=%0d local=%0d global=%0d): bpu_nxpc2_valid=%0d, ky vong 0 (fetch_ready=0)", c, l, g, o.outv));
      tbl = {tbl, $sformatf("       %0d          %0d         %0d     |    %0d    |    %0d    | %-6s%s\n",
                            c, l, g, expp, o.pt, c ? "global" : "local", (o.pt === expp) ? "" : "   <== SAI")};
    end
    note({tbl, "   ------------------------------------------------------------\n",
               "   Ket luan: bo chon la MUX 2->1 thuan; choice[1] la chan chon, khong\n",
               "   co dieu kien nao khac xen vao (khong phu thuoc btb_valid_nxpc2).\n",
               "================================================================"});

    //---- C: nhanh chon LOCAL -- doi nxpc2 doi ket qua, doi GHR thi KHONG ----
    phase_of("C_source_local");
    bd_set_choice    (cidx_tk, `WNT);    bd_set_choice    (cidx_nt, `WNT);
    bd_set_local_pht (lidx_tk, `ST);     bd_set_local_pht (lidx_nt, `SNT);
    bd_set_global_pht(gidx_tk, `SNT);    bd_set_global_pht(gidx_nt, `SNT);
    observe_at(ADDR_TK, 2'd2, o);
    observe_at(ADDR_NT, 2'd2, o2);
    note($sformatf("C nguon LOCAL: nxpc2=TK -> local_pht[0x%03h]=%02b predT=%0d ; nxpc2=NT -> local_pht[0x%03h]=%02b predT=%0d",
                   lidx_tk, o.lp, o.pt, lidx_nt, o2.lp, o2.pt));
    chk(o.pt === 1'b1 && o2.pt === 1'b0, $sformatf("C: doi nxpc2 phai doi du doan khi choice[1]=0 (do duoc %0d va %0d, ky vong 1 va 0)", o.pt, o2.pt));
    bd_set_ghr(10'h155);                 // GHR chi doi chi muc GLOBAL -> nhanh local phai tro
    observe_at(ADDR_TK, 2'd2, o2);
    chk(o2.pt === 1'b1, $sformatf("C: doi GHR (0x000 -> 0x155) khong duoc lam doi du doan khi choice[1]=0, do duoc %0d", o2.pt));
    bd_set_ghr(10'd0);

    //---- D: nhanh chon GLOBAL -- doi GHR doi ket qua, doi nxpc2 cung doi ----
    phase_of("D_source_global");
    bd_set_choice    (cidx_tk, `WT);     bd_set_choice    (cidx_nt, `WT);
    bd_set_local_pht (lidx_tk, `ST);     bd_set_local_pht (lidx_nt, `ST);    // local=1 o ca hai
    bd_set_global_pht(gidx_tk,   `ST);   // ghr=0     -> doc o nay
    bd_set_global_pht(gidx_skew, `SNT);  // ghr=0x155 -> doc o nay
    bd_set_global_pht(gidx_nt,   `SNT);
    bd_set_ghr(10'd0);     observe_at(ADDR_TK, 2'd2, o);
    bd_set_ghr(10'h155);   observe_at(ADDR_TK, 2'd2, o2);
    note($sformatf("D nguon GLOBAL: ghr=0x000 -> global_pht[%0d]=%02b predT=%0d ; ghr=0x155 -> global_pht[%0d]=%02b predT=%0d (local[1]=1 o ca hai)",
                   gidx_tk, o.gp, o.pt, gidx_skew, o2.gp, o2.pt));
    chk(o.pt === 1'b1 && o2.pt === 1'b0, $sformatf("D: doi GHR phai doi du doan khi choice[1]=1 (do duoc %0d va %0d, ky vong 1 va 0)", o.pt, o2.pt));
    chk(o2.lp[1] === 1'b1, "D: local[1] phai van bang 1 khi GHR doi -- neu khong thi phep do khong tach duoc hai nguon");
    bd_set_ghr(10'd0);
    observe_at(ADDR_NT, 2'd2, o2);
    chk(o2.pt === 1'b0, $sformatf("D: doi nxpc2 phai doi du doan khi choice[1]=1, do duoc %0d (ky vong 0)", o2.pt));
    bd_restore_all();
    check_restored(lidx_tk, gidx_tk, cidx_tk, sav_l_tk, sav_g_tk, sav_c_tk, sav_ghr);
    chk(bd.read_local_pht(lidx_nt) === sav_l_nt, $sformatf("khoi phuc: local_pht[0x%03h]=%02b, ky vong %02b", lidx_nt, bd.read_local_pht(lidx_nt), sav_l_nt));

    //---- E: on dinh -- giu nguyen ngo vao 50 chu ky, ngo ra khong duoc doi --
    phase_of("E_stable_50_cycles");
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_TK), .opcode(OPC_NOP));
    o = snap();
    note($sformatf("E: giu nguyen ngo vao (nxpc2=ADDR_TK) -- moc: predT=%0d bpu_nxpc2=0x%08h vld=%0d flush=%0d", o.pt, o.outp, o.outv, o.fl));
    chk(o.outv === 1'b1, "E: moc phai co bpu_nxpc2_valid=1 (BTB trung + du doan re) thi phep do moi co nghia");
    for (int k = 0; k < 50; k++) begin
      apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_TK), .opcode(OPC_NOP));
      o2 = snap();
      if (o2.pt !== o.pt || o2.outp !== o.outp || o2.outv !== o.outv || o2.fl !== o.fl)
        chk(1'b0, $sformatf("E: chu ky %0d doi ngo ra du ngo vao khong doi: predT=%0d nxpc2=0x%08h vld=%0d flush=%0d", k, o2.pt, o2.outp, o2.outv, o2.fl));
    end
    chk(bd.read_btb_valid(cidx_tk) === 1'b1, "E: 50 chu ky nghi da xoa btb_valid[TK]");
    chk(bd.read_local_bht(cidx_tk) === lidx_tk, "E: 50 chu ky nghi da lam doi local_bht[TK] du is_branch = 0");
    chk(bd.read_ghr() === sav_ghr, $sformatf("E: 50 chu ky nghi da lam doi GHR (0x%03h -> 0x%03h)", sav_ghr, bd.read_ghr()));
    bus_free();
  endtask
endclass : predict_mux_nxpc2_test


//==============================================================================
// 8.2 predict_index_alignment
//
// Sheet -- Flow: dat hai dia chi nxpc2 trung bit [11:2] nhung khac bit cao (cach
//   nhau boi so cua 4 KB); quan sat du doan va btb_valid_nxpc2.
// Sheet -- Pass: hai dia chi trung chi muc cho cung ket qua du doan va cung
//   trang thai BTB -- trung chi muc do KHONG co truong tag (DesignNotes R1).
// RTL Ref: bpu_reg.v
//==============================================================================
class predict_index_alignment_test extends bpu_scene_base;
  `bpu_test_utils(predict_index_alignment_test, "8.2")

  virtual task test_body();
    bpu_fetch_obs_t base_o, o;
    bpu_pipe_obs_t  p0[4], p1[4];
    bit [31:0] alias_a[5] = '{32'h0000_0100, 32'h0000_1100, 32'h0000_2100, 32'h0000_3100, 32'hFFFF_F100};
    bit [31:0] miss_a = 32'h0000_0104;   // idx 65, chua bao gio duoc ghi
    string     s;

    //---- A: huan luyen mot dia chi ------------------------------------------
    phase_of("A_train_base");
    setup_addresses();
    chk(bd.read_btb_valid(bpu_idx(ADDR_TK))  === 1'b1, "chuan bi: btb_valid[TK] phai = 1");
    chk(bd.read_btb_target(bpu_idx(ADDR_TK)) === (ADDR_TK + 32'h40),
        $sformatf("chuan bi: btb_target[TK]=0x%08h, ky vong 0x%08h", bd.read_btb_target(bpu_idx(ADDR_TK)), ADDR_TK + 32'h40));

    //---- B: nam dia chi trung pc[11:2], cach nhau boi so 4 KB ---------------
    phase_of("B_alias_4KB_multiples");
    observe_at(alias_a[0], 2'd0, base_o);
    show_fetch("B moc (nxpc2 = 0x100)", alias_a[0], base_o);
    chk(base_o.hit === 1'b1, "B: moc phai co btb_valid_nxpc2=1 thi phep so sanh moi co nghia");
    s = {"\n=== 8.2 TRUNG CHI MUC KHI KHONG CO TRUONG TAG (DesignNotes R1, phia du doan) ===\n",
         "   nxpc2        [11:2]  btb_valid  btb_target   local  global  choice  predT\n",
         "   -----------------------------------------------------------------------\n"};
    foreach (alias_a[k]) begin
      observe_at(alias_a[k], 2'd0, o);
      s = {s, $sformatf("   0x%08h   %4d       %0d      0x%08h    %0d      %0d       %0d      %0d\n",
                        alias_a[k], alias_a[k][11:2], o.hit, o.tgt, o.lp[1], o.gp[1], o.ch[1], o.pt)};
      chk(alias_a[k][11:2] === alias_a[0][11:2], $sformatf("chuan bi B: 0x%08h khong trung [11:2] voi moc", alias_a[k]));
      chk(o.hit === base_o.hit, $sformatf("B 0x%08h: btb_valid_nxpc2=%0d khac moc %0d", alias_a[k], o.hit, base_o.hit));
      chk(o.tgt === base_o.tgt, $sformatf("B 0x%08h: btb_target_nxpc2=0x%08h khac moc 0x%08h", alias_a[k], o.tgt, base_o.tgt));
      chk(o.lp  === base_o.lp,  $sformatf("B 0x%08h: local_pht_data_nxpc2=%02b khac moc %02b (chi muc local_bht[nxpc2] cung trung)", alias_a[k], o.lp, base_o.lp));
      chk(o.gp  === base_o.gp,  $sformatf("B 0x%08h: global_pht_data_nxpc2=%02b khac moc %02b", alias_a[k], o.gp, base_o.gp));
      chk(o.ch  === base_o.ch,  $sformatf("B 0x%08h: choice_data_nxpc2=%02b khac moc %02b", alias_a[k], o.ch, base_o.ch));
      chk(o.pt  === base_o.pt,  $sformatf("B 0x%08h: predict_taken_nxpc2=%0d khac moc %0d", alias_a[k], o.pt, base_o.pt));
    end
    note({s, "   -----------------------------------------------------------------------\n",
             "   Nam dia chi cach nhau boi so 4 KB deu cho CUNG mot ket qua: BTB khong\n",
             "   luu tag (bpu_reg.v) va ca ba chi muc du doan (local_bht[nxpc2],\n",
             "   nxpc2 ^ ghr, choice[nxpc2]) deu chi lay pc[11:2].\n",
             "==========================================================================="});

    //---- C: doi chung -- dia chi KHAC [11:2] phai truot ---------------------
    phase_of("C_negative_control");
    chk(miss_a[11:2] !== alias_a[0][11:2], "chuan bi C: dia chi doi chung phai khac [11:2]");
    observe_at(miss_a, 2'd0, o);
    show_fetch("C doi chung (0x104, idx 65)", miss_a, o);
    chk(o.hit === 1'b0, $sformatf("C: btb_valid_nxpc2=%0d tai 0x104 (idx 65), ky vong 0 -- phep so o pha B khong duoc vacuous", o.hit));

    //---- D: he qua that -- dia chi la CHIEM duoc duong chuyen huong ---------
    phase_of("D_alias_hijacks_redirect");
    bus_free();
    pipe_probe(.pc(32'h0000_0B00), .nxpc2(32'h0000_0100), .taken(1'b1), .o(p0));
    pipe_probe(.pc(32'h0000_0B00), .nxpc2(32'h0000_3100), .taken(1'b1), .o(p1));
    note($sformatf({
      "\n=== 8.2 pha D: dia chi la o tang fetch chiem duoc duong chuyen huong ===\n",
      "  nxpc2 = 0x00000100 -> tai F: vld=%0d nxpc2=0x%08h\n",
      "  nxpc2 = 0x00003100 -> tai F: vld=%0d nxpc2=0x%08h  (cach 0x100 dung 12 KB)\n",
      "  Bo doan re toi mot dia chi CHUA TUNG duoc ghi, vi BTB tra loi theo chi muc.\n",
      "====================================================================="},
      p0[0].bpu_nxpc2_valid, p0[0].bpu_nxpc2, p1[0].bpu_nxpc2_valid, p1[0].bpu_nxpc2));
    chk(p0[0].bpu_nxpc2_valid === 1'b1, "D: moc 0x100 phai lam f_valid=1");
    chk(p1[0].bpu_nxpc2_valid === p0[0].bpu_nxpc2_valid,
        $sformatf("D: 0x3100 cho bpu_nxpc2_valid=%0d, moc 0x100 cho %0d", p1[0].bpu_nxpc2_valid, p0[0].bpu_nxpc2_valid));
    chk(p1[0].bpu_nxpc2 === p0[0].bpu_nxpc2,
        $sformatf("D: 0x3100 cho bpu_nxpc2=0x%08h, moc 0x100 cho 0x%08h", p1[0].bpu_nxpc2, p0[0].bpu_nxpc2));
  endtask
endclass : predict_index_alignment_test
