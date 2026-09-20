//------------------------------------------------------------------------------
// FILE: tests/t06_choice_tests.sv -- Nhom 6: Choice (bo chon tournament)
//   6.1 choice_no_update
//   6.2 choice_update_and_saturation
//   6.3 choice_carry_source
//   6.4 choice_pc_independence
//
// Canh dung (R_00..R_11, ADDR_P, choice_step) o lib/bpu_scene_base.sv SECTION 3.
// bpu_predictor.v so local_carry voi global_carry -- hai bit du doan doc tai
// nxpc2 o THOI DIEM FETCH, mang xuong hai chu ky -- nen moi phep do deu dat
// canh o chu ky F (nxpc2 = R) va cap branch_taken o F+2 (pc = P).
//------------------------------------------------------------------------------


//==============================================================================
// 6.1 choice_no_update
//
// Sheet -- Flow: ba truong hop rieng biet; moi truong hop day nhanh qua du ba
//   tang de carry-down co gia tri xac dinh truoc khi danh gia.
// Sheet -- Pass: choice_wr_en = 0 va gia tri choice giu nguyen trong ca ba.
// RTL Ref: bpu_predictor.v
//==============================================================================
class choice_no_update_test extends bpu_scene_base;
  `bpu_test_utils(choice_no_update_test, "6.1")

  virtual task test_body();
    bit       lc, gc, wren;
    bit [1:0] b, a;

    phase_of("A_build_scene");
    build_choice_scene();
    assert_choice_scene("A");

    //---- B: KHONG PHAI lenh re nhanh (is_branch = 0), canh van BAT DONG -----
    phase_of("B_not_a_branch");
    choice_step(.R(R_10), .P(ADDR_P), .taken(1'b0), .cidx(P_IDX),
                .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a), .is_branch(1'b0));
    chk(lc !== gc, $sformatf("B: carry=(%0d,%0d) -- can BAT DONG thi phep kiem moi co nghia", lc, gc));
    chk(wren === 1'b0, $sformatf("B: choice_wr_en=%0d voi is_branch=0, ky vong 0", wren));
    chk(a === b, $sformatf("B: choice[%0d] %s -> %s, ky vong giu nguyen", P_IDX, bpu_ctr_name(b), bpu_ctr_name(a)));
    note($sformatf("B (is_branch=0) : carry=(%0d,%0d) bat dong, btb_valid_pc=1 -> choice_wr_en=%0d, choice[%0d] giu %s",
                   lc, gc, wren, P_IDX, bpu_ctr_name(a)));

    //---- C: btb_valid_pc = 0 (ADDR_NB chua bao gio la pc) -------------------
    phase_of("C_btb_valid_pc_zero");
    chk(bd.read_btb_valid(NB_IDX) === 1'b0, $sformatf("chuan bi C: btb_valid[%0d] phai = 0", NB_IDX));
    choice_step(.R(R_10), .P(ADDR_NB), .taken(1'b0), .cidx(NB_IDX),
                .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
    chk(lc !== gc, $sformatf("C: carry=(%0d,%0d) -- can BAT DONG", lc, gc));
    chk(wren === 1'b0, $sformatf("C: choice_wr_en=%0d voi btb_valid_pc=0, ky vong 0", wren));
    chk(a === b, $sformatf("C: choice[%0d] %s -> %s, ky vong giu nguyen", NB_IDX, bpu_ctr_name(b), bpu_ctr_name(a)));
    note($sformatf("C (btb_valid_pc=0): carry=(%0d,%0d) bat dong, is_branch=1 -> choice_wr_en=%0d, choice[%0d] giu %s",
                   lc, gc, wren, NB_IDX, bpu_ctr_name(a)));

    //---- D: local_carry == global_carry (DONG THUAN), ca hai gia tri taken --
    // Dung lai canh cho TUNG truong hop: buoc co branch_taken=1 lam GHR dich va
    // chi muc global cua R lech ngay o truong hop ke tiep.
    phase_of("D_carry_agree");
    for (int k = 0; k < 4; k++) begin
      bit [31:0] R  = k[1] ? R_11 : R_00;
      bit        tk = k[0];
      build_choice_scene();
      assert_choice_scene($sformatf("D o %0d", k));
      choice_step(.R(R), .P(ADDR_P), .taken(tk), .cidx(P_IDX),
                  .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
      chk(lc === gc, $sformatf("D: nxpc2=0x%08h cho carry=(%0d,%0d) -- canh dung SAI, can DONG THUAN", R, lc, gc));
      chk(wren === 1'b0, $sformatf("D: carry=(%0d,%0d) taken=%0d -> choice_wr_en=%0d, ky vong 0 (dong thuan)", lc, gc, tk, wren));
      chk(a === b, $sformatf("D: carry=(%0d,%0d) taken=%0d -> choice[%0d] %s -> %s, ky vong giu nguyen",
                             lc, gc, tk, P_IDX, bpu_ctr_name(b), bpu_ctr_name(a)));
      note($sformatf("D dong thuan (%0d,%0d) taken=%0d -> choice_wr_en=%0d, choice[%0d] giu %s",
                     lc, gc, tk, wren, P_IDX, bpu_ctr_name(a)));
    end

    //---- E: doi chung -- cung khung do NHUNG du dieu kien -> PHAI ghi -------
    phase_of("E_positive_control");
    choice_step(.R(R_10), .P(ADDR_P), .taken(1'b0), .cidx(P_IDX),
                .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
    chk(lc !== gc, $sformatf("E: carry=(%0d,%0d) -- can BAT DONG", lc, gc));
    chk(wren === 1'b1, $sformatf("E: choice_wr_en=%0d khi du ca ba dieu kien, ky vong 1", wren));
    chk(a === bpu_upd_ctr(b, 1'b1), $sformatf("E: choice[%0d] %s -> %s, ky vong %s",
        P_IDX, bpu_ctr_name(b), bpu_ctr_name(a), bpu_ctr_name(bpu_upd_ctr(b, 1'b1))));
    note($sformatf("E doi chung: du ca ba dieu kien -> choice_wr_en=1, choice[%0d] %s -> %s",
                   P_IDX, bpu_ctr_name(b), bpu_ctr_name(a)));
    bus_free();
  endtask
endclass : choice_no_update_test


//==============================================================================
// 6.2 choice_update_and_saturation
//
// Sheet -- Flow: tao bat dong local khac global tai thoi diem fetch; day nhanh
//   qua du ba tang roi cap branch_taken tai execute; lap muoi lan cho chieu
//   global dung, sau do muoi lan cho chieu local dung.
// Sheet -- Pass: bo dem tien ve phia global khi global_carry dung va ve phia
//   local khi local_carry dung; dung tai ST sau khi bao hoa roi giam dan ve SNT.
// RTL Ref: bpu_predictor.v ; bpu_ctrl.v
//==============================================================================
class choice_update_and_saturation_test extends bpu_scene_base;
  `bpu_test_utils(choice_update_and_saturation_test, "6.2")

  string tbl;

  // 10 buoc voi canh R, carry ky vong (el, eg), branch_taken = 0; dem so buoc
  // dung yen o trang thai bao hoa `sat`.
  local task automatic ten_steps(string tag, bit [31:0] R, bit el, bit eg, bit [1:0] sat, output int n_sat);
    bit lc, gc, wren;  bit [1:0] b, a, e;
    n_sat = 0;
    for (int k = 0; k < 10; k++) begin
      choice_step(.R(R), .P(ADDR_P), .taken(1'b0), .cidx(P_IDX),
                  .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
      e = bpu_exp_choice(b, el, eg, 1'b0, 1'b1);
      chk(lc === el && gc === eg, $sformatf("%s buoc %0d: carry=(%0d,%0d), canh dung SAI (can %0d,%0d)", tag, k+1, lc, gc, el, eg));
      chk(wren === 1'b1, $sformatf("%s buoc %0d: choice_wr_en=%0d, ky vong 1", tag, k+1, wren));
      chk(a === e, $sformatf("%s buoc %0d: choice[%0d] %s -> %s, ky vong %s",
                             tag, k+1, P_IDX, bpu_ctr_name(b), bpu_ctr_name(a), bpu_ctr_name(e)));
      if (b === sat && a === sat) n_sat++;
      tbl = {tbl, $sformatf("    %2d  | (%0d,%0d) |   %0d   | %s -> %s          | %s\n",
                            k+1, lc, gc, wren, bpu_ctr_name(b), bpu_ctr_name(a), bpu_ctr_name(e))};
    end
    chk(bd.read_choice(P_IDX) === sat, $sformatf("%s: sau 10 buoc choice[%0d]=%s, ky vong %s",
        tag, P_IDX, bpu_ctr_name(bd.read_choice(P_IDX)), bpu_ctr_name(sat)));
    chk(n_sat >= 6, $sformatf("%s: chi co %0d buoc o trang thai bao hoa %s -- chua chung minh duoc no KHONG tran/muon",
        tag, n_sat, bpu_ctr_name(sat)));
  endtask

  virtual task test_body();
    bit       lc, gc, wren;
    bit [1:0] b, a, e;
    int       n_sat;

    phase_of("A_build_scene");
    build_choice_scene();
    assert_choice_scene("A");
    note($sformatf("A: choice[%0d] xuat phat tu %s, btb_valid=%0d, ghr=0x%03h",
                   P_IDX, bpu_ctr_name(bd.read_choice(P_IDX)), bd.read_btb_valid(P_IDX), bd.read_ghr()));

    //---- B: carry=(1,0), taken=0 => GLOBAL dung -> tien len, bao hoa ST -----
    // taken=0 con giu GHR = 0 (chen bit 0 vao GHR dang 0) nen canh dung khong troi.
    phase_of("B_ten_steps_toward_global");
    tbl = "\n=== 6.2 QUY DAO BO DEM CHOICE ===\n";
    tbl = {tbl, "  Pha B: carry=(local=1, global=0), branch_taken=0 -> GLOBAL dung -> tien len\n",
                "   buoc | carry | wr_en | choice truoc -> sau | ky vong\n",
                "   -----+-------+-------+---------------------+--------\n"};
    ten_steps("B", R_10, 1'b1, 1'b0, `ST, n_sat);

    //---- C: carry=(0,1), taken=0 => LOCAL dung -> giam dan, bao hoa SNT -----
    phase_of("C_ten_steps_toward_local");
    tbl = {tbl, "  Pha C: carry=(local=0, global=1), branch_taken=0 -> LOCAL dung -> giam dan\n",
                "   buoc | carry | wr_en | choice truoc -> sau | ky vong\n",
                "   -----+-------+-------+---------------------+--------\n"};
    ten_steps("C", R_01, 1'b0, 1'b1, `SNT, n_sat);
    note({tbl, "   Bo dem dung han tai ST va tai SNT, khong tran vong.\n======================================="});

    //---- D: quet du TAM o cua cx_choice_update_table -----------------------
    // Moi o dung lai canh, nap bo dem ve WT (tu WT ca ba ket qua tang/giam/giu
    // deu quan sat duoc).
    phase_of("D_sweep_eight_cells");
    tbl = {"\n=== 6.2 TAM O CUA cx_choice_update_table ===\n",
           "   local global taken | wr_en | choice truoc -> sau | ky vong | huong\n",
           "   -------------------+-------+---------------------+---------+--------\n"};
    for (int k = 0; k < 8; k++) begin
      bit tk = k[2];  bit el = k[1];  bit eg = k[0];
      bit [31:0] R = el ? (eg ? R_11 : R_10) : (eg ? R_01 : R_00);
      string dir;
      build_choice_scene();
      repeat (2) choice_step(.R(R_10), .P(ADDR_P), .taken(1'b0), .cidx(P_IDX),   // nap ve WT
                             .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
      chk(a === `WT, $sformatf("D o %0d: nap bo dem ve WT that bai, dang o %s", k, bpu_ctr_name(a)));
      choice_step(.R(R), .P(ADDR_P), .taken(tk), .cidx(P_IDX),
                  .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
      e = bpu_exp_choice(b, el, eg, tk, 1'b1);
      chk(lc === el && gc === eg, $sformatf("D o %0d: carry=(%0d,%0d), canh dung SAI (can %0d,%0d)", k, lc, gc, el, eg));
      chk(wren === (el !== eg), $sformatf("D o %0d: choice_wr_en=%0d, ky vong %0d", k, wren, (el !== eg)));
      chk(a === e, $sformatf("D o %0d (l=%0d g=%0d taken=%0d): choice %s -> %s, ky vong %s",
                             k, el, eg, tk, bpu_ctr_name(b), bpu_ctr_name(a), bpu_ctr_name(e)));
      dir = (a === b) ? "giu" : (a > b) ? "tang" : "giam";
      tbl = {tbl, $sformatf("     %0d     %0d      %0d    |   %0d   | %s -> %s          | %s     | %s\n",
                            el, eg, tk, wren, bpu_ctr_name(b), bpu_ctr_name(a), bpu_ctr_name(e), dir)};
    end
    note({tbl, "   -------------------+-------+---------------------+---------+--------\n",
               "   local == global -> choice_wr_en = 0, bo dem dung yen o ca hai gia tri taken.\n",
               "   local != global -> tien ve phia bo du doan trung voi branch_taken.\n",
               "======================================="});
    bus_free();
  endtask
endclass : choice_update_and_saturation_test


//==============================================================================
// 6.3 choice_carry_source
//
// Sheet -- Flow: dung tinh huong ma gia tri local/global tai chu ky F khac voi
//   gia tri doc duoc tai F+2 (GHR da dich, PHT bi nhanh khac ghi de); quan sat
//   huong cap nhat cua bo chon.
// Sheet -- Pass: bo chon cap nhat theo local_carry/global_carry (gia tri tai F).
// RTL Ref: bpu_ctrl.v ; bpu_predictor.v
//
// Mot dia chi A duy nhat lam nxpc2 tai F va pc tai F+2. Nhanh xen vao tai F+1
// (khong re) lam doi CA HAI duong doc cua A:
//   (a) GHR 1 -> 2 : chi muc global cua A doi 257 -> 258 (hai o NGUOC nhau)
//   (b) nhanh xen vao co local_bht = 0 nhu A -> ghi de local_pht[0]: WT -> WNT
// => tai F doc (1,0), tai F+2 doc (0,1). Voi branch_taken = 0:
//   nguon carry-down (dung) -> TIEN LEN ; nguon execute-time (sai) -> GIAM.
//==============================================================================
class choice_carry_source_test extends bpu_scene_base;
  `bpu_test_utils(choice_carry_source_test, "6.3")

  localparam bit [31:0] A_ADDR = 32'h0000_0400;   // idx 256 -- nxpc2 tai F VA pc tai F+2
  localparam int        A_IDX  = 256;
  localparam bit [31:0] X_ADDR = 32'h0000_0D00;   // idx 832 -- nhanh XEN VAO tai F+1
  localparam bit [31:0] Z_ADDR = 32'h0000_0E00;   // idx 896 -- dat GHR = 1
  localparam bit [31:0] G_ADDR = 32'h0000_0408;   // idx 258 -- nap global_pht[258] = WT

  virtual task test_body();
    bpu_fetch_obs_t o;
    bit       lF, gF, lX, gX, lc, gc, wren;
    bit [9:0] ghr_x2;
    bit [1:0] b, a, e_carry, e_exec;

    //---- A: dung canh va kiem tien de ---------------------------------------
    // Sau day: GHR = 1, A co btb_valid = 1 va local_bht = 0, local_pht[0] = WT,
    // global_pht[257] = SNT, global_pht[258] = WT.
    phase_of("A_arm_and_assert");
    build_choice_scene();                       // GHR = 0, local_pht[0] = WT
    drive_branch(A_ADDR, 1'b0, 32'h40);         // A: btb_valid = 1, local_bht van = 0
    drive_branch(G_ADDR, 1'b0, 32'h40);         // idx 258, btb_valid_pc=0 -> global_pht[258] = WT
    drive_branch(X_ADDR, 1'b0, 32'h40);         // X: btb_valid = 1, local_bht van = 0
    drive_branch(Z_ADDR, 1'b1, 32'h40);         // GHR: 0 -> 1
    chk(bd.read_ghr() === 10'd1, $sformatf("A: ghr=0x%03h, canh dung can 1", bd.read_ghr()));
    chk(bd.read_btb_valid(A_IDX) === 1'b1, "A: btb_valid[A] phai = 1 (dieu kien choice_wr_en)");
    chk(bd.read_local_bht(A_IDX) === 12'd0, $sformatf("A: local_bht[A]=0x%03h, canh dung can 0 (de A doc local_pht[0])", bd.read_local_bht(A_IDX)));
    observe_at(A_ADDR, 2'd0, o);
    lF = o.lp[1]; gF = o.gp[1];
    chk(lF === 1'b1 && gF === 1'b0, $sformatf("A: tai F doc duoc (local,global)=(%0d,%0d), canh dung can (1,0)", lF, gF));

    //---- B: phep do -- ba chu ky lien tiep ----------------------------------
    phase_of("B_measure");
    b = bd.read_choice(A_IDX);
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(A_ADDR), .opcode(OPC_NOP));          // F : chot carry
    apply(.pc(X_ADDR), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),        // F+1: nhanh xen vao
          .is_branch(1'b1), .taken(1'b0), .offset(32'h40));
    apply(.pc(A_ADDR), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),        // F+2: nhanh cua A
          .is_branch(1'b1), .taken(1'b0), .offset(32'h40));
    lc   = bd.read_local_carry();               // nguon THAT: gia tri tai F
    gc   = bd.read_global_carry();
    lX   = bd.read_local_pht_data_pc()[1];      // nguon DOI CHUNG: gia tri tai F+2
    gX   = bd.read_global_pht_data_pc()[1];
    wren = bd.read_choice_wr_en();
    ghr_x2 = bd.read_ghr();
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP));
    a = bd.read_choice(A_IDX);

    //---- C: doi chieu hai gia thuyet ----------------------------------------
    phase_of("C_discriminate");
    e_carry = bpu_exp_choice(b, lc, gc, 1'b0, 1'b1);   // neu dung carry-down (gia tri F)
    e_exec  = bpu_exp_choice(b, lX, gX, 1'b0, 1'b1);   // neu dung gia tri doc tai F+2
    chk(lc === 1'b1 && gc === 1'b0, $sformatf("C: local_carry/global_carry = (%0d,%0d), canh dung can (1,0)", lc, gc));
    chk(lX === 1'b0 && gX === 1'b1, $sformatf("C: doc theo pc tai F+2 = (%0d,%0d), canh dung can (0,1) -- phai NGUOC voi tai F", lX, gX));
    chk(e_carry !== e_exec, $sformatf("C: hai gia thuyet cho cung ket qua %s -- phep do KHONG phan biet duoc", bpu_ctr_name(e_carry)));
    chk(wren === 1'b1, $sformatf("C: choice_wr_en=%0d, ky vong 1", wren));
    chk(a === e_carry, $sformatf("C: choice[%0d] %s -> %s. Nguon CARRY-DOWN cho %s, nguon EXECUTE-TIME cho %s -> RTL dang dung nguon SAI",
        A_IDX, bpu_ctr_name(b), bpu_ctr_name(a), bpu_ctr_name(e_carry), bpu_ctr_name(e_exec)));
    note($sformatf({
      "\n=== 6.3 NGUON GIA TRI CAP NHAT BO CHON ===\n",
      "  Mot dia chi 0x%08h di qua ca ba tang; mot nhanh khac xen vao tai F+1.\n",
      "    tai F   (nxpc2) : local=%0d global=%0d   <- gia tri duoc CHOT vao carry-down\n",
      "    tai F+2 (pc)    : local=%0d global=%0d   <- gia tri neu doc lai luc execute\n",
      "    GHR 0x001 -> 0x%03h tai F+2 => chi muc global doi 257 -> 258\n",
      "    local_pht[0] bi nhanh xen vao ghi de => bit local doi 1 -> 0\n",
      "  branch_taken = 0: carry-down (dung) -> %s -> %s ; gia tri F+2 (sai) -> %s -> %s\n",
      "  DO DUOC: choice[%0d] %s -> %s  ==> RTL dung CARRY-DOWN.\n",
      "======================================="},
      A_ADDR, lc, gc, lX, gX, ghr_x2,
      bpu_ctr_name(b), bpu_ctr_name(e_carry), bpu_ctr_name(b), bpu_ctr_name(e_exec),
      A_IDX, bpu_ctr_name(b), bpu_ctr_name(a)));
    bus_free();
  endtask
endclass : choice_carry_source_test


//==============================================================================
// 6.4 choice_pc_independence
//
// Sheet -- Flow: phat mau cap nhat nguoc nhau tai cac PC khong trung chi muc va
//   tai cac PC trung chi muc.
// Sheet -- Pass: khong trung: hai bo dem doc lap. Trung chi muc: lan ghi sau thang.
// RTL Ref: bpu_reg.v
//==============================================================================
class choice_pc_independence_test extends bpu_scene_base;
  `bpu_test_utils(choice_pc_independence_test, "6.4")

  virtual task test_body();
    bit       lc, gc, wren;
    bit [1:0] b, a, p2_start;

    //---- A: dung canh, them ADDR_P2 vao BTB ---------------------------------
    phase_of("A_build_scene");
    build_choice_scene();
    drive_branch(ADDR_P2, 1'b0, 32'h40);    // btb_valid -> 1, bht van 0, GHR khong dich
    assert_choice_scene("A");
    chk(bd.read_btb_valid(P2_IDX) === 1'b1, $sformatf("A: btb_valid[%0d] phai = 1", P2_IDX));
    chk(bpu_idx(ADDR_P) !== bpu_idx(ADDR_P2), "chuan bi A: hai PC nay phai KHAC chi muc");
    chk(bpu_idx(ADDR_P) === bpu_idx(ADDR_PA), "chuan bi A: ADDR_PA phai TRUNG chi muc voi ADDR_P");

    //---- B: hai PC KHONG trung chi muc -> hai bo dem doc lap ---------------
    // Nap choice[P2] len ST truoc (o SNT thi ba buoc "di xuong" khong doi duoc).
    phase_of("B_distinct_indices");
    repeat (3) choice_step(.R(R_10), .P(ADDR_P2), .taken(1'b0), .cidx(P2_IDX),
                           .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
    chk(a === `ST, $sformatf("B: nap choice[%0d] len ST that bai, dang o %s", P2_IDX, bpu_ctr_name(a)));
    p2_start = bd.read_choice(P2_IDX);
    note($sformatf("B: xuat phat choice[%0d]=%s choice[%0d]=%s",
                   P_IDX, bpu_ctr_name(bd.read_choice(P_IDX)), P2_IDX, bpu_ctr_name(p2_start)));
    for (int k = 0; k < 3; k++) begin
      // P: tien LEN
      choice_step(.R(R_10), .P(ADDR_P), .taken(1'b0), .cidx(P_IDX),
                  .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
      chk(lc === 1'b1 && gc === 1'b0, $sformatf("B buoc %0d (P): carry=(%0d,%0d), can (1,0)", k, lc, gc));
      chk(a === bpu_upd_ctr(b, 1'b1), $sformatf("B buoc %0d: choice[%0d] %s -> %s, ky vong %s",
          k, P_IDX, bpu_ctr_name(b), bpu_ctr_name(a), bpu_ctr_name(bpu_upd_ctr(b, 1'b1))));
      chk(bd.read_choice(P2_IDX) === p2_start, $sformatf(
          "B buoc %0d: cap nhat tai pc=0x%08h da lam doi choice[%0d] (%s -> %s) -- hai bo dem KHONG doc lap",
          k, ADDR_P, P2_IDX, bpu_ctr_name(p2_start), bpu_ctr_name(bd.read_choice(P2_IDX))));
      // P2: tien XUONG
      choice_step(.R(R_01), .P(ADDR_P2), .taken(1'b0), .cidx(P2_IDX),
                  .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
      chk(lc === 1'b0 && gc === 1'b1, $sformatf("B buoc %0d (P2): carry=(%0d,%0d), can (0,1)", k, lc, gc));
      chk(a === bpu_upd_ctr(b, 1'b0), $sformatf("B buoc %0d: choice[%0d] %s -> %s, ky vong %s",
          k, P2_IDX, bpu_ctr_name(b), bpu_ctr_name(a), bpu_ctr_name(bpu_upd_ctr(b, 1'b0))));
      p2_start = a;
    end
    note($sformatf("B: sau 3 cap buoc nguoc chieu -- choice[%0d]=%s (di LEN), choice[%0d]=%s (di XUONG)",
                   P_IDX, bpu_ctr_name(bd.read_choice(P_IDX)), P2_IDX, bpu_ctr_name(bd.read_choice(P2_IDX))));
    chk(bd.read_choice(P_IDX) !== bd.read_choice(P2_IDX), "B: hai bo dem ket thuc bang nhau -- phep kiem doc lap khong con y nghia");

    //---- C: hai PC TRUNG chi muc -> dung chung mot o, lan sau thang ---------
    phase_of("C_aliased_indices");
    build_choice_scene();
    repeat (2) choice_step(.R(R_10), .P(ADDR_P), .taken(1'b0), .cidx(P_IDX),   // nap ve WT
                           .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
    chk(a === `WT, $sformatf("C: nap bo dem ve WT that bai, dang o %s", bpu_ctr_name(a)));
    choice_step(.R(R_01), .P(ADDR_PA), .taken(1'b0), .cidx(P_IDX),   // ADDR_PA = P + 4 KB, cung idx 768
                .lc(lc), .gc(gc), .wren(wren), .ch_b(b), .ch_a(a));
    chk(lc === 1'b0 && gc === 1'b1, $sformatf("C: carry=(%0d,%0d), can (0,1)", lc, gc));
    chk(wren === 1'b1, $sformatf("C: choice_wr_en=%0d khi pc=0x%08h, ky vong 1 -- btb_valid doc theo chi muc nen dia chi la van trung", wren, ADDR_PA));
    chk(a === bpu_upd_ctr(b, 1'b0), $sformatf("C: pc=0x%08h ghi vao choice[%0d]: %s -> %s, ky vong %s",
        ADDR_PA, P_IDX, bpu_ctr_name(b), bpu_ctr_name(a), bpu_ctr_name(bpu_upd_ctr(b, 1'b0))));
    note($sformatf({
      "\n=== 6.4 PC TRUNG CHI MUC DUNG CHUNG MOT O ===\n",
      "  pc=0x%08h va pc=0x%08h cach nhau 4 KB, deu cho pc[11:2] = %0d.\n",
      "  Bo dem duoc pc=0x%08h nap len %s, roi pc=0x%08h ghi de xuong %s.\n",
      "  Lan ghi sau THANG: bpu_reg.v chi lay chi muc, khong luu tag.\n",
      "======================================="},
      ADDR_P, ADDR_PA, P_IDX, ADDR_P, bpu_ctr_name(b), ADDR_PA, bpu_ctr_name(a)));
    bus_free();
  endtask
endclass : choice_pc_independence_test
