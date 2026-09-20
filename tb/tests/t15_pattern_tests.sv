//------------------------------------------------------------------------------
// FILE: tests/t15_pattern_tests.sv -- Nhom 15: Branch Pattern
//   15.1 pattern_saturating_and_cold
//   15.2 pattern_alternating
//   15.3 pattern_loop_12b
//   15.4 pattern_correlated
//   15.5 pattern_btb_aliasing
//   15.6 pattern_nested_loop
//
// Tat ca chay tren bpu_coherent_gen (make_gen): dia chi di nxpc2(T) -> nxpc(T+1)
// -> pc(T+2), nen quyet dinh tang fetch thuoc ve DUNG nhanh dang duoc giai
// quyet. Moi NGUONG deu duoc TINH TU SO DO THUC voi kich thich nay. Cac nhanh
// cach nhau GAP = 2 chu ky (xem bpu_scene_base SECTION 5). Nhat quan duong ong
// va X duoc kiem tu dong o report_phase (gen_final_checks).
//------------------------------------------------------------------------------


//==============================================================================
// 15.1 pattern_saturating_and_cold
//
// Sheet -- Flow: 100 nhanh luon-re roi 100 nhanh luon-khong-re tai mot PC; sau
//   do mot nhanh CHUA TUNG GAP de quan sat cold start.
// Sheet -- Pass: bo dem bao hoa hoi tu (so lan doan sai co bien tren); nhanh
//   cold gay BTB truot va bpu_flush = 2.
//
// BANG CHUNG DINH LUONG CUA LOI ICH HYBRID: ban decode mat mot bong bong o MOI
// nhanh cua mau luon-re (bpu_flush = 1) ke ca khi doan dung; ban hybrid tra BTB
// ngay o tang FETCH nen sau khi hoi tu bpu_flush = 0. Pha B do dung con so do.
//==============================================================================
class pattern_saturating_and_cold_test extends bpu_scene_base;
  `bpu_test_utils(pattern_saturating_and_cold_test, "15.1")

  //   SO DO: luon-re 12 doan sai / 100 ; luon-khong-re 2/100 -> tong 14.
  //          Bien 25 (~1.8 lan) -- du cho dao dong nho, van bat duoc bo dem
  //          khong hoi tu (se cho hang chuc den 100 lan).
  localparam int  MISPREDICT_MAX    = 25;
  //   SO DO: 60/60 = 100.0% bpu_flush = 0 o doan on dinh. Day la khang dinh
  //          CAU TRUC: sau khi bao hoa, mau luon-re KHONG duoc phep con bong bong.
  localparam real STEADY_FLUSH0_MIN = 100.0;
  localparam int  WARM   = 100;
  localparam int  STEADY = 60;

  virtual task test_body();
    int ids_t[$], ids_nt[$];
    bit pat_t[], pat_nt[];
    bpu_flush_tally_t tt, tnt, tst;
    bpu_reference  r = tb.module_env.reference;
    bpu_pipe_obs_t o;
    int m0, miss0, icold;
    make_gen(32'd2);

    //---- A: 100 luon-re roi 100 luon-khong-re -------------------------------
    phase_of("A_saturating_convergence");
    pat_t  = new[WARM]; foreach (pat_t[i])  pat_t[i]  = 1'b1;
    pat_nt = new[WARM]; foreach (pat_nt[i]) pat_nt[i] = 1'b0;
    run_pattern(32'h0000_0100, pat_t,  ids_t);
    run_pattern(32'h0000_0100, pat_nt, ids_nt);
    gen.drain();
    tt  = tally(ids_t);
    tnt = tally(ids_nt);
    show_tally("pha luon-re",       tt);
    show_tally("pha luon-khong-re", tnt);

    //---- B: BANG CHUNG HYBRID -- doan on dinh cua mau luon-re ---------------
    phase_of("B_hybrid_flush0_evidence");
    tst = tally_from(ids_t, ids_t.size() - STEADY);
    note($sformatf(
      {"\n=== 15.1 BANG CHUNG DINH LUONG LOI ICH HYBRID ===\n",
       "  Mau LUON-RE, %0d nhanh cuoi (da hoi tu):\n",
       "    bpu_flush = 0 : %0d/%0d = %.1f%%   <-- ban hybrid: chuyen huong tai tang FETCH\n",
       "    bpu_flush = 1 : %0d/%0d = %.1f%%\n",
       "    bpu_flush = 2 : %0d/%0d = %.1f%%\n",
       "  Ban DECODE cho mau nay se ra bpu_flush = 1 o MOI nhanh (100%%).\n",
       "================================================="},
      tst.n, tst.n_flush0, tst.n, bpu_pct(tst.n_flush0, tst.n),
      tst.n_flush1, tst.n, bpu_pct(tst.n_flush1, tst.n),
      tst.n_flush2, tst.n, bpu_pct(tst.n_flush2, tst.n)));
    chk(bpu_pct(tst.n_flush0, tst.n) >= STEADY_FLUSH0_MIN, $sformatf(
        "doan on dinh chi dat %.1f%% bpu_flush=0 (< %.1f%%) -- khong chung minh duoc loi ich hybrid",
        bpu_pct(tst.n_flush0, tst.n), STEADY_FLUSH0_MIN));
    chk((tt.n_flush2 + tnt.n_flush2) <= MISPREDICT_MAX, $sformatf(
        "tong doan sai %0d vuot bien %0d -- bo dem khong hoi tu", tt.n_flush2 + tnt.n_flush2, MISPREDICT_MAX));

    //---- C: cold start -- mot PC chua tung gap ------------------------------
    phase_of("C_cold_start");
    icold = bpu_idx(32'h0000_0500);      // = 320
    chk(bd.read_btb_valid(icold) === 1'b0, $sformatf("btb_valid[%0d] da duoc dat truoc khi lai nhanh cold", icold));
    m0    = r.mispredicts;
    miss0 = r.btb_misses_at_branch;
    gen.push_branch(.pc(32'h0000_0500), .taken(1'b0));   // chua gap + khong re
    gen.drain();
    o = gen.obs_of(gen.last_id);
    note($sformatf("nhanh cold: bpu_flush=%0d  d_mispredict=%0d  d_btb_miss=%0d (ky vong 2, 1, 1)",
                   o.bpu_flush, r.mispredicts - m0, r.btb_misses_at_branch - miss0));
    chk(o.bpu_flush === 2'd2, $sformatf("nhanh cold cho bpu_flush=%0d, ky vong 2 (BTB truot + mac dinh doan re)", o.bpu_flush));
    chk(r.mispredicts - m0 == 1, $sformatf("delta doan sai = %0d, ky vong 1", r.mispredicts - m0));
    chk(r.btb_misses_at_branch - miss0 == 1, $sformatf("delta BTB truot = %0d, ky vong 1", r.btb_misses_at_branch - miss0));
  endtask
endclass : pattern_saturating_and_cold_test


//==============================================================================
// 15.2 pattern_alternating
//
// Sheet -- Pass: mau xen ke duoc hoc (so doan sai co bien tren); hai lich su
//   nguoc nhau hoi tu ve hai o global_pht doi lap.
//
//   Mau xen ke tai pc=0x100 (pc_index = 64) lam GHR di vao hai trang thai on
//   dinh 682 (0b1010101010) va 341 (0b0101010101). Chi muc gshare = pc_index ^ ghr:
//        64 ^ 682 = 746   (lich su ket thuc bang RE      -> hoi tu ST)
//        64 ^ 341 = 277   (lich su ket thuc bang KHONG RE -> hoi tu SNT)
//==============================================================================
class pattern_alternating_test_hyb extends bpu_scene_base;
  `bpu_test_utils(pattern_alternating_test_hyb, "15.2")

  //   SO DO: 0 doan sai / 176 nhanh sau 24 nhanh hoc. Bien 4 -- mau de nhat
  //          trong nhom, bat cu doan sai nao sau khi hoc deu dang ngo.
  localparam int MISPREDICT_MAX = 4;
  localparam int LEN            = 200;
  localparam int WARM           = 24;

  virtual task test_body();
    int ids[$];
    bit pat[];
    bpu_flush_tally_t tall, tst;
    bit [1:0] e746, e277;
    make_gen(32'd2);

    //---- A: 200 nhanh xen ke ------------------------------------------------
    phase_of("A_alternating_learned");
    pat = new[LEN];
    foreach (pat[i]) pat[i] = (i % 2 == 0);
    run_pattern(32'h0000_0100, pat, ids);
    gen.drain();
    tall = tally(ids);
    tst  = tally_from(ids, WARM);
    show_tally("toan chuoi", tall);
    show_tally($sformatf("sau %0d nhanh hoc", WARM), tst);
    chk(tst.n_flush2 <= MISPREDICT_MAX, $sformatf(
        "doan sai o doan on dinh = %0d, vuot bien %0d -- mau xen ke khong duoc hoc", tst.n_flush2, MISPREDICT_MAX));

    //---- B: hai lich su nguoc nhau -> hai o global_pht doi lap --------------
    phase_of("B_gshare_entries_diverge");
    e746 = bd.read_global_pht(746);
    e277 = bd.read_global_pht(277);
    note($sformatf("global_pht[746]=2'b%02b (ky vong ST 11)   global_pht[277]=2'b%02b (ky vong SNT 00)", e746, e277));
    chk(e746 === `ST,  $sformatf("global_pht[746]=2'b%02b, ky vong ST -- lich su ket thuc bang RE phai hoi tu luon-re", e746));
    chk(e277 === `SNT, $sformatf("global_pht[277]=2'b%02b, ky vong SNT -- lich su ket thuc bang KHONG RE phai hoi tu luon-khong-re", e277));
    chk(e746[1] !== e277[1], "hai o gshare KHONG phan ky -- khong chung minh duoc gshare tach duoc hai lich su");
  endtask
endclass : pattern_alternating_test_hyb


//==============================================================================
// 15.3 pattern_loop_12b
//
// Sheet -- Pass: vong lap NGAN HON lich su thi hoc duoc (doan sai gan 0 sau khi
//   on dinh); vong lap DAI HON lich su thi khong hoc duoc het.
//
//   BHT rong 12 bit: lich su bao hoa 0xFFF sau 12 nhanh, o local_pht[0xFFF] chi
//   BAT DAU duoc ghi tu nhanh thu 13 -> can ~24 vong khoi dong.
//   Chu ky 5  (< 12): moi vi tri co lich su 12 bit RIENG -> hoc duoc.
//   Chu ky 21 (> 12): nhieu vi tri chia nhau cung lich su -> khong doan truoc duoc.
//==============================================================================
class pattern_loop_12b_test extends bpu_scene_base;
  `bpu_test_utils(pattern_loop_12b_test, "15.3")

  localparam int WARM_LOOPS  = 24;
  localparam int CYC5_LOOPS  = 40;
  localparam int CYC21_LOOPS = 12;
  //   SO DO: chu ky 5 -> 0/200 (0.0%) ; chu ky 21 -> 12/252 (4.8%), 1 lan moi vong.
  localparam int SHORT_MAX   = 6;    // "phai hoc duoc"
  localparam int LONG_MIN    = 8;    // "phai KHONG hoc duoc het"

  virtual task test_body();
    int ids5[$], ids21[$];
    bpu_flush_tally_t t5, t21;
    real r5, r21;
    make_gen(32'd2);

    phase_of("A_cycle5_fits_12b");
    run_loop(32'h0000_0100, 5, WARM_LOOPS, CYC5_LOOPS, ids5);
    gen.drain();
    t5 = tally(ids5);
    show_tally("chu ky 5 (sau khoi dong)", t5);

    phase_of("B_cycle21_exceeds_12b");          // PC khac de khong dung chung BHT/PHT
    run_loop(32'h0000_0300, 21, WARM_LOOPS, CYC21_LOOPS, ids21);
    gen.drain();
    t21 = tally(ids21);
    show_tally("chu ky 21 (sau khoi dong)", t21);

    phase_of("C_compare");
    r5  = bpu_pct(t5.n_flush2,  t5.n);
    r21 = bpu_pct(t21.n_flush2, t21.n);
    note($sformatf(
      {"\n=== 15.3 RANH GIOI LICH SU 12 BIT ===\n",
       "  chu ky 5  (5 < 12) : doan sai %0d/%0d = %.1f%%\n",
       "  chu ky 21 (21 > 12): doan sai %0d/%0d = %.1f%%\n",
       "  Ket luan: vong lap ngan hon lich su thi hoc duoc, dai hon thi khong.\n",
       "======================================"},
      t5.n_flush2, t5.n, r5, t21.n_flush2, t21.n, r21));
    chk(t5.n_flush2  <= SHORT_MAX, $sformatf("chu ky 5: doan sai %0d vuot bien %0d -- le ra phai hoc duoc", t5.n_flush2, SHORT_MAX));
    chk(t21.n_flush2 >= LONG_MIN,  $sformatf("chu ky 21: doan sai %0d duoi %0d -- le ra phai KHONG hoc duoc het", t21.n_flush2, LONG_MIN));
    chk(r21 > r5, $sformatf("ti le doan sai chu ky 21 (%.1f%%) khong cao hon chu ky 5 (%.1f%%) -- ranh gioi 12 bit khong hien ra", r21, r5));
  endtask
endclass : pattern_loop_12b_test


//==============================================================================
// 15.4 pattern_correlated
//
// Sheet -- Flow: A tai 0x100 ngau nhien, B tai 0x200 bang A (tuong quan hoan
//   toan). Local o B that bai; gshare bat duoc tuong quan qua GHR.
// Sheet -- Pass: global chinh xac hon local; choice tai B hoi tu ve global
//   (MSB = 1); ti le doan sai tai B duoi 5%.
//
//   Nguon bit: bpu_det_rng seed 2 -- tat dinh. Phep kiem choice MSB NHAY VOI SEED.
//   SO DO ti le doan sai tai B theo so cap: 200 -> 23.9% ; 400 -> 3.0% ;
//   800 -> 1.0% (chon) ; 1600 -> 0.8%. Nguong sheet 5% -> bien 5 lan.
//==============================================================================
class pattern_correlated_test_hyb extends bpu_scene_base;
  `bpu_test_utils(pattern_correlated_test_hyb, "15.4")

  localparam int  PAIRS      = 800;
  localparam int  WARM       = 400;
  localparam real B_RATE_MAX = 5.0;

  virtual task test_body();
    int ids_a[$], ids_b[$];
    bpu_flush_tally_t ta, tb_tally, tbs;
    bpu_reference r = tb.module_env.reference;
    bit [1:0] ch_b;
    bit a;
    make_gen(32'd2);

    phase_of("A_correlated_pairs");
    for (int k = 0; k < PAIRS; k++) begin
      a = gen.rnd_bit();
      gen.push_branch(.pc(32'h0000_0100), .taken(a)); ids_a.push_back(gen.last_id); gen.idle(GAP);
      gen.push_branch(.pc(32'h0000_0200), .taken(a)); ids_b.push_back(gen.last_id); gen.idle(GAP);
    end
    gen.drain();
    ta       = tally(ids_a);
    tb_tally = tally(ids_b);
    tbs      = tally_from(ids_b, WARM);
    show_tally("A (0x100, ngau nhien)", ta);
    show_tally("B (0x200, = A)",        tb_tally);
    show_tally($sformatf("B sau %0d nhanh hoc", WARM), tbs);

    phase_of("B_global_beats_local");
    ch_b = bd.read_choice(10'd128);   // chi muc cua pc=0x200
    note($sformatf("global_correct=%0d  local_correct=%0d  choice[128]=2'b%02b (MSB=%0b)",
                   r.global_correct_count, r.local_correct_count, ch_b, ch_b[1]));
    chk(r.global_correct_count > r.local_correct_count, $sformatf(
        "global_correct(%0d) khong lon hon local_correct(%0d) -- gshare khong thang", r.global_correct_count, r.local_correct_count));
    chk(ch_b[1] === 1'b1, $sformatf("choice[128]=2'b%02b -- MSB chua bat, bo chon chua hoi tu ve global (NHAY SEED)", ch_b));

    phase_of("C_B_mispredict_rate");
    note($sformatf("ti le doan sai tai B (sau khoi dong) = %.1f%% (sheet: < 5%%)", bpu_pct(tbs.n_flush2, tbs.n)));
    chk(bpu_pct(tbs.n_flush2, tbs.n) < B_RATE_MAX, $sformatf(
        "ti le doan sai tai B = %.1f%%, vuot %.1f%%", bpu_pct(tbs.n_flush2, tbs.n), B_RATE_MAX));
  endtask
endclass : pattern_correlated_test_hyb


//==============================================================================
// 15.5 pattern_btb_aliasing
//
// Sheet -- Flow: hai nhanh o hai PC KHAC NHAU nhung TRUNG chi muc BTB, chay xen
//   ke voi hai chu ky khac nhau -> suy giam co kiem soat.
//   THEM (DesignNotes R1 trong workload that): mot dia chi KHONG PHAI LENH RE
//   trung chi muc voi nhanh da nam trong BTB -> tang fetch van chuyen huong NHAM
//   vi BTB tra thuan theo chi muc, khong tag, khong biet opcode.
//==============================================================================
class pattern_btb_aliasing_test_hyb extends bpu_scene_base;
  `bpu_test_utils(pattern_btb_aliasing_test_hyb, "15.5")

  localparam int  ITER         = 100;
  //   SO DO: tron hai chu ky tren cung o BTB -> 81/200 = 40.5%. Nguong "phai
  //          suy giam" 25%: tut duoi thi hai mau khong con tranh nhau mot o.
  localparam real ALIAS_MIN    = 25.0;
  localparam int  NONBR_PROBES = 20;
  localparam bit [31:0] PC_A = 32'h0000_0100;   // idx 64
  localparam bit [31:0] PC_B = 32'h0000_1100;   // idx 64 (trung)

  virtual task test_body();
    int ids_all[$];
    bpu_flush_tally_t tall;
    int n_spurious = 0, n_pre_ok = 0, n_fetch_before;
    make_gen(32'd2);
    chk(bpu_idx(PC_A) == bpu_idx(PC_B), $sformatf("tien de sai: 0x%08h va 0x%08h KHONG trung chi muc (%0d vs %0d)",
        PC_A, PC_B, bpu_idx(PC_A), bpu_idx(PC_B)));

    //---- A: hai chu ky khac nhau tren cung mot o BTB ------------------------
    phase_of("A_two_periods_same_index");
    for (int k = 0; k < ITER; k++) begin
      gen.push_branch(.pc(PC_A), .taken((k % 7) != 6)); ids_all.push_back(gen.last_id); gen.idle(GAP);
      gen.push_branch(.pc(PC_B), .taken((k % 5) != 4)); ids_all.push_back(gen.last_id); gen.idle(GAP);
    end
    gen.drain();
    tall = tally(ids_all);
    show_tally("tron hai chu ky (trung chi muc)", tall);
    chk(tall.n == 2 * ITER, $sformatf("chi %0d/%0d nhanh duoc xu ly -- co the treo", tall.n, 2 * ITER));
    chk(bpu_pct(tall.n_flush2, tall.n) > ALIAS_MIN, $sformatf(
        "ti le doan sai %.1f%% khong cao hon %.1f%% -- suy giam do trung chi muc khong hien ra", bpu_pct(tall.n_flush2, tall.n), ALIAS_MIN));

    //---- B: dia chi KHONG phai lenh re, trung chi muc (R1) ------------------
    // Dua BTB[64] ve DOAN RE MANH bang 24 nhanh luon-re tai PC_A (BHT 12 bit:
    // local_pht[0xFFF] chi bat dau duoc ghi tu nhanh thu 13).
    phase_of("B_non_branch_aliases_btb_entry");
    for (int k = 0; k < 24; k++) begin gen.push_branch(.pc(PC_A), .taken(1'b1)); gen.idle(GAP); end
    gen.drain();
    chk(bd.read_btb_valid(64) === 1'b1, "tien de sai: BTB[64] chua hop le -- pha A phai huan luyen no truoc");
    for (int k = 0; k < NONBR_PROBES; k++) begin
      // is_branch = 0 VA fetch_opcode = ADDI: d_valid = 0 va corr_valid = 0; neu
      // MUX van chuyen huong thi nguon duy nhat la tang FETCH. Phai do o CHU KY
      // dia chi nay o tang FETCH -> dem qua n_fetch_wins cua bo sinh.
      n_fetch_before = gen.n_fetch_wins;
      gen.push_branch(.pc(PC_B), .taken(1'b0), .opcode(OPC_NOP), .is_branch(1'b0));
      if (bd.read_btb_valid_nxpc2() && bd.read_predict_taken_nxpc2()) n_pre_ok++;   // tien de
      if (gen.n_fetch_wins > n_fetch_before) n_spurious++;
      gen.drain();
    end
    chk(n_pre_ok > 0, $sformatf(
        "tien de chua dat o ca %0d lan thu: btb_valid_nxpc2 && predict_taken_nxpc2 khong bao gio cung bang 1, chua the ket luan gi ve R1", NONBR_PROBES));
    note($sformatf(
      {"\n=== 15.5 CA MOI -- DesignNotes R1 trong workload that ===\n",
       "  Dia chi 0x%08h KHONG phai lenh re (fetch_opcode=ADDI, is_branch=0)\n",
       "  nhung trung chi muc BTB (%0d) voi nhanh 0x%08h da duoc huan luyen.\n",
       "  Tien de dat (BTB hop le VA dang doan RE): %0d/%0d\n",
       "  So lan tang FETCH van thang MUX (chuyen huong nham): %0d/%0d\n",
       "  BTB tra thuan theo chi muc, khong tag va khong biet opcode, nen chuyen\n",
       "  huong nham la HE QUA CAU TRUC -- ghi nhan, khong phai loi RTL.\n",
       "========================================================"},
      PC_B, bpu_idx(PC_B), PC_A, n_pre_ok, NONBR_PROBES, n_spurious, NONBR_PROBES));
    chk(n_spurious > 0, $sformatf("khong lan nao trong %0d lan quan sat duoc chuyen huong nham -- canh chua dung dung", NONBR_PROBES));
  endtask
endclass : pattern_btb_aliasing_test_hyb


//==============================================================================
// 15.6 pattern_nested_loop
//
// Sheet -- Flow: vong ngoai N=30, vong trong N=4 (TTTN), kem mot nhanh dieu kien.
// Sheet -- Pass: ti le doan sai tong duoi mot bien (15%; SO DO 20/270 = 7.4%).
//==============================================================================
class pattern_nested_loop_test_hyb extends bpu_scene_base;
  `bpu_test_utils(pattern_nested_loop_test_hyb, "15.6")

  localparam int  OUTER    = 30;
  localparam int  INNER    = 4;
  localparam real RATE_MAX = 15.0;

  virtual task test_body();
    int ids[$];
    bpu_flush_tally_t t;
    make_gen(32'd2);

    phase_of("A_nested_loop");
    for (int o = 0; o < OUTER; o++) begin
      for (int i = 0; i < INNER; i++) begin
        gen.push_branch(.pc(32'h0000_0100), .taken(i < 3)); ids.push_back(gen.last_id); gen.idle(GAP);   // vong trong TTTN
        gen.push_branch(.pc(32'h0000_0300), .taken(i < 2)); ids.push_back(gen.last_id); gen.idle(GAP);   // nhanh dieu kien
      end
      gen.push_branch(.pc(32'h0000_0200), .taken(o < OUTER - 1)); ids.push_back(gen.last_id); gen.idle(GAP);   // vong ngoai
    end
    gen.drain();
    t = tally(ids);
    show_tally("vong lap long nhau", t);
    chk(bpu_pct(t.n_flush2, t.n) < RATE_MAX, $sformatf("ti le doan sai %.1f%% vuot %.1f%%", bpu_pct(t.n_flush2, t.n), RATE_MAX));
  endtask
endclass : pattern_nested_loop_test_hyb
