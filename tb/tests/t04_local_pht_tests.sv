//------------------------------------------------------------------------------
// FILE: tests/t04_local_pht_tests.sv -- Nhom 4: Local PHT (Pshare)
//   4.1 local_bht_shift_12b
//   4.2 local_pht_counter_and_init
//   4.3 pshare_index_two_stage
//   4.4 local_pht_rw_all_4096
//------------------------------------------------------------------------------


//==============================================================================
// 4.1 local_bht_shift_12b
//
// Sheet -- Flow: phat mot mau tai pc=0x100 va mot mau khac tai pc=0x200 xen ke;
//   doc bang lich su bang backdoor sau moi buoc.
// Sheet -- Pass: bang lich su dich dung theo mau; bit cu nhat bi day ra sau 12
//   lan dich (KHONG phai 6); lich su tai PC con lai khong thay doi.
// RTL Ref: bpu_predictor.v ; bpu_reg.v
//==============================================================================
class local_bht_shift_12b_test extends bpu_scene_base;
  `bpu_test_utils(local_bht_shift_12b_test, "4.1")

  local function void chk_bht(int idx, bit [11:0] exp, string lbl);
    chk(bd.read_local_bht(idx) === exp,
        $sformatf("%s: local_bht[%0d]=0x%03h, ky vong 0x%03h", lbl, idx, bd.read_local_bht(idx), exp));
  endfunction

  virtual task test_body();
    bit pat_a[8] = '{1'b1,1'b1,1'b1,1'b0,1'b1,1'b1,1'b0,1'b1};   // -> 12'h0ED
    bit pat_b[6] = '{1'b0,1'b1,1'b0,1'b0,1'b1,1'b0};             // -> 12'h012

    //---- A: dich dung theo mau, doc lap theo tung PC (phat XEN KE) ---------
    phase_of("A_shift_and_independence");
    for (int k = 0; k < 8; k++) begin
      drive_branch(32'h0000_0100, pat_a[k]);
      if (k < 6) drive_branch(32'h0000_0200, pat_b[k]);
    end
    chk_bht(64,  12'h0ED, "8 lan dich, 12 bit khong mat bit");
    chk_bht(128, 12'h012, "doc lap theo PC");

    //---- B: bit cu nhat bi day ra sau DUNG 12 lan dich ---------------------
    // Ep lich su ve 0, phat 1 TAKEN roi 12 NOT-TAKEN: sau 12 dich bit 1 o
    // bit[11] (12'h800), sau dich thu 13 moi bi day ra. Bang 6 bit se ve 0 ngay
    // sau 6 dich -> test fail.
    phase_of("B_oldest_bit_drops_at_12");
    bd.deposit_local_bht(300, 12'h000);                   // pc=0x4B0 -> idx 300
    drive_branch(32'h0000_04B0, 1'b1);
    chk_bht(300, 12'h001, "sau 1 dich");
    repeat (5) drive_branch(32'h0000_04B0, 1'b0);
    chk_bht(300, 12'h020, "sau 6 dich -- neu 0x000 thi bang chi rong 6 bit");
    repeat (5) drive_branch(32'h0000_04B0, 1'b0);
    chk_bht(300, 12'h400, "sau 11 dich");
    drive_branch(32'h0000_04B0, 1'b0);
    chk_bht(300, 12'h800, "sau 12 dich (bit cu nhat VAN o bit[11])");
    drive_branch(32'h0000_04B0, 1'b0);
    chk_bht(300, 12'h000, "sau 13 dich (bit cu nhat DA bi day ra)");
  endtask
endclass : local_bht_shift_12b_test


//==============================================================================
// 4.2 local_pht_counter_and_init
//
// Sheet -- Flow: phat nhanh dau tien tai pc chua tung gap (BTB miss), sau do
//   lap lai cung pc de tao BTB hit; tiep tuc bang chuoi taken/not-taken phu moi
//   chuyen trang thai, ke ca vuot qua ST va SNT.
// Sheet -- Pass: lan gap dau: PHT = WT bat ke branch_taken. Cac lan sau: bo dem
//   theo dung SNT-WNT-WT-ST va giu nguyen khi bao hoa o hai dau.
// RTL Ref: bpu_predictor.v
//==============================================================================
class local_pht_counter_and_init_test extends bpu_scene_base;
  `bpu_test_utils(local_pht_counter_and_init_test, "4.2")

  virtual task test_body();
    //---- A: lan gap dau (BTB miss) -> WT du branch_taken = 0 ---------------
    // Not-taken nen local_bht[64] van = 0 -> ca hai lan deu dung chi muc 0.
    phase_of("A_init_WT_on_miss");
    drive_chk_local_pht(32'h0000_0100, 1'b0, 0, `WT, "lan gap dau (init bat ke taken)");

    //---- B: lan gap thu hai (BTB hit) -> cap nhat bo dem -------------------
    phase_of("B_update_on_hit");
    drive_chk_local_pht(32'h0000_0100, 1'b0, 0, `WNT, "lan gap hai (WT--)");

    //---- C: init WT tai mot chi muc KHAC -----------------------------------
    phase_of("C_init_WT_other_index");
    bd.deposit_local_bht(448, 12'd100);                   // pc=0x700 -> idx 448
    bd.deposit_local_pht(100, `SNT);
    drive_chk_local_pht(32'h0000_0700, 1'b1, 100, `WT, "init chi muc 100");

    //---- D: phu MOI chuyen trang thai + hai bien bao hoa -------------------
    // local_bht[64] phai GIU 0 suot 8 nhanh (RTL ghi lich su da dich vao sau
    // moi nhanh) -> BUOC phai force; phan tu mang khong goi ten nen pha nay
    // chay duoc tren Xcelium chu KHONG tren Questa (vsim-16133).
    // BTB chi can deposit: RTL chi bao gio ghi btb_valid <= 1, khong xoa.
    phase_of("D_all_transitions_and_saturation");
    bd.force_local_bht(64, 12'd0);
    bd.deposit_btb(64, 1'b1, 32'h0000_0140);
    bd.deposit_local_pht(0, `SNT);
    drive_chk_local_pht(32'h0000_0100, 1'b1, 0, `WNT, "len 1: SNT->WNT");
    drive_chk_local_pht(32'h0000_0100, 1'b1, 0, `WT,  "len 2: WNT->WT");
    drive_chk_local_pht(32'h0000_0100, 1'b1, 0, `ST,  "len 3: WT->ST");
    drive_chk_local_pht(32'h0000_0100, 1'b1, 0, `ST,  "bao hoa tren: ST->ST (khong tran)");
    drive_chk_local_pht(32'h0000_0100, 1'b0, 0, `WT,  "xuong 1: ST->WT");
    drive_chk_local_pht(32'h0000_0100, 1'b0, 0, `WNT, "xuong 2: WT->WNT");
    drive_chk_local_pht(32'h0000_0100, 1'b0, 0, `SNT, "xuong 3: WNT->SNT");
    drive_chk_local_pht(32'h0000_0100, 1'b0, 0, `SNT, "bao hoa duoi: SNT->SNT (khong muon)");
    bd.release_local_bht(64);
  endtask
endclass : local_pht_counter_and_init_test


//==============================================================================
// 4.3 pshare_index_two_stage
//
// Sheet -- Flow: phat chuoi tai pc=0x100 roi tao cung gia tri lich su tai
//   pc=0x200; quan sat chi muc o chu ky co ghi; sau do dat pc va nxpc2 tro hai
//   chi muc co lich su khac nhau trong cung mot chu ky.
// Sheet -- Pass: chi muc PHT bang local_bht[pc_index] hien tai va lan ghi dung
//   lich su CU; hai PC cung lich su tro vao cung entry; local_pht_data_pc va
//   local_pht_data_nxpc2 dung hai chi muc khac nhau trong cung chu ky.
// RTL Ref: bpu_reg.v
//==============================================================================
class pshare_index_two_stage_test extends bpu_scene_base;
  `bpu_test_utils(pshare_index_two_stage_test, "4.3")

  virtual task test_body();
    bit [11:0] ipc, inx;
    bit [1:0]  dpc, dnx;
    scoreboard_not_applicable("phai ghim local_bht/local_pht de co hai lich su khac nhau tai pc va nxpc2 trong cung chu ky");

    //---- A: lan ghi dung lich su CU ----------------------------------------
    // bht[64]=5, BTB miss -> nhanh taken ghi WT vao pht[5] (chi muc CU), sau do
    // bht dich 5 -> 11; pht[11] phai con nguyen.
    phase_of("A_write_uses_old_history");
    bd.deposit_btb(64, 1'b0, 32'h0);
    bd.deposit_local_bht(64, 12'd5);
    drive_branch(32'h0000_0100, 1'b1);
    chk(bd.read_local_pht(5)  === `WT,  $sformatf("pht[5]=2'b%02b, ky vong WT (ghi tai chi muc CU 5)", bd.read_local_pht(5)));
    chk(bd.read_local_pht(11) === `SNT, $sformatf("pht[11]=2'b%02b, ky vong SNT (chi muc MOI khong duoc ghi)", bd.read_local_pht(11)));
    chk(bd.read_local_bht(64) === 12'h00B, $sformatf("bht[64]=0x%03h, ky vong 0x00B (5 dich trai + 1)", bd.read_local_bht(64)));

    //---- B: hai PC cung lich su -> cung entry ------------------------------
    // Deposit du: moi PC chi lai DUNG MOT nhanh, va RTL doc lich su TRUOC canh len.
    phase_of("B_same_history_same_entry");
    bd.deposit_local_bht(64,  12'd20);
    bd.deposit_local_bht(128, 12'd20);
    bd.deposit_btb(64,  1'b1, 32'h0000_0140);
    bd.deposit_btb(128, 1'b1, 32'h0000_0240);
    bd.deposit_local_pht(20, `SNT);
    drive_chk_local_pht(32'h0000_0100, 1'b1, 20, `WNT, "dung chung entry qua pc1");
    drive_chk_local_pht(32'h0000_0200, 1'b1, 20, `WT,  "pc2 cung lich su cap nhat cung entry");

    //---- C: duong doc phia pc va phia nxpc2 DOC LAP trong cung chu ky ------
    //   pc    = 0x100 -> bht[64]  = 0x111 -> local_pht[0x111] = ST
    //   nxpc2 = 0x200 -> bht[128] = 0x222 -> local_pht[0x222] = SNT
    // Chi DOC duong to hop (is_branch = 0) nen deposit la du.
    phase_of("C_pc_vs_nxpc2_independent");
    bd.deposit_local_bht(64,  12'h111);
    bd.deposit_local_bht(128, 12'h222);
    bd.deposit_local_pht(12'h111, `ST);
    bd.deposit_local_pht(12'h222, `SNT);
    bd.force_predict_inputs(.pc(32'h0000_0100), .nxpc(NEU_NXPC), .fetch_opcode(OPC_NOP),
                            .branch_target_fetch(32'h0), .flush_in(2'b00), .halt(1'b0),
                            .nxpc2(32'h0000_0200));
    #2ns;
    ipc = rd_reg("local_pht_index_pc");
    inx = rd_reg("local_pht_index_nxpc2");
    dpc = bd.read_local_pht_data_pc();
    dnx = bd.read_local_pht_data_nxpc2();
    chk(ipc === 12'h111, $sformatf("local_pht_index_pc=0x%03h, ky vong 0x111", ipc));
    chk(inx === 12'h222, $sformatf("local_pht_index_nxpc2=0x%03h, ky vong 0x222", inx));
    chk(ipc !== inx, "hai chi muc BANG nhau -- duong doc pc va nxpc2 khong doc lap");
    chk(dpc === `ST,  $sformatf("local_pht_data_pc=2'b%02b, ky vong ST", dpc));
    chk(dnx === `SNT, $sformatf("local_pht_data_nxpc2=2'b%02b, ky vong SNT", dnx));
    chk(dpc !== dnx, "hai gia tri BANG nhau -- khong chung minh duoc tinh doc lap trong cung chu ky");
    bd.release_predict_inputs();
  endtask
endclass : pshare_index_two_stage_test


//==============================================================================
// 4.4 local_pht_rw_all_4096
//
// Sheet -- Flow: dung backdoor ep local_bht de quet chi muc h = 0..4095, ghi
//   roi doc lai tung entry.
// Sheet -- Pass: moi local_pht[h] ghi va doc doc lap; khong entry nao bi gop do
//   cat bit chi muc.
// RTL Ref: bpu_reg.v
//
//   A. DINH DIA CHI: quet DU 4096 chi muc bang duong ghi THAT: ghim bht=h, dat
//      pht[h]=SNT, phat 1 nhanh taken, kiem pht[h]==WNT. Neu chi muc bi cat bit
//      thi entry h>=64 khong bao gio doi.
//   B. DOC LAP LUU TRU: ghi 4096 gia tri phan biet roi doc lai.
//==============================================================================
class local_pht_rw_all_4096_test extends bpu_scene_base;
  `bpu_test_utils(local_pht_rw_all_4096_test, "4.4")

  virtual task test_body();
    int n_bad;

    //---- A: quet DU 4096 chi muc qua duong ghi that ------------------------
    // Dat lai chi muc o DAU moi vong va chi lai MOT nhanh sau do, nen deposit
    // du: RTL doc local_bht[64] truoc canh len, tuc gia tri vua dat.
    phase_of("A_addressing_sweep_4096");
    bd.deposit_btb(64, 1'b1, 32'h0000_0140);     // BTB hit -> di duong cap nhat
    n_bad = 0;
    for (int h = 0; h < 4096; h++) begin
      bd.deposit_local_bht(64, h[11:0]);
      bd.deposit_local_pht(h, `SNT);
      drive_branch(32'h0000_0100, 1'b1);         // pht[h]: SNT -> WNT
      if (bd.read_local_pht(h) !== `WNT)
        sweep_bad(n_bad, $sformatf("pht[%0d]=2'b%02b, ky vong WNT (entry khong toi duoc / bi cat bit)", h, bd.read_local_pht(h)));
    end
    sweep_report("dinh dia chi 4096 entry", n_bad, 4096);

    //---- B: doc lap luu tru tren ca 4096 entry (0 thoi gian mo phong) ------
    phase_of("B_storage_independence_4096");
    for (int h = 0; h < 4096; h++) bd.deposit_local_pht(h, h[1:0]);
    n_bad = 0;
    for (int h = 0; h < 4096; h++)
      if (bd.read_local_pht(h) !== h[1:0])
        sweep_bad(n_bad, $sformatf("luu tru: pht[%0d]=2'b%02b, ky vong 2'b%02b", h, bd.read_local_pht(h), h[1:0]));
    sweep_report("doc lap luu tru 4096 entry", n_bad, 4096);
  endtask
endclass : local_pht_rw_all_4096_test
