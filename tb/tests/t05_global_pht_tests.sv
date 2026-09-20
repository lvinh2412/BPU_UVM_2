//------------------------------------------------------------------------------
// FILE: tests/t05_global_pht_tests.sv -- Nhom 5: Global PHT (Gshare)
//   5.1 gshare_index_and_skew
//   5.2 global_pht_counter_and_init
//   5.3 gshare_aliasing
//   5.4 global_pht_rw_all
//------------------------------------------------------------------------------


//==============================================================================
// 5.1 gshare_index_and_skew
//
// Sheet -- Flow: nap truoc cac entry; dat pc khac nxpc2 trong cung chu ky va so
//   hai chi muc; dich GHR bang chuoi nhanh lien tiep; ghi nhan chi muc dung cho
//   du doan va chi muc dung cho cap nhat cua CUNG mot nhanh.
// Sheet -- Pass: global_pc_index = pc_index XOR ghr va global_nxpc2_index =
//   nxpc2_index XOR ghr; cung dia chi doc ra entry khac nhau khi GHR thay doi;
//   carry-down chi mang xuong BIT du doan chu khong mang chi muc, nen hai chi
//   muc cua cung mot nhanh co the khac nhau (DesignNotes N2).
// RTL Ref: bpu_reg.v ; bpu_ctrl.v
//==============================================================================
class gshare_index_and_skew_test extends bpu_scene_base;
  `bpu_test_utils(gshare_index_and_skew_test, "5.1")

  virtual task test_body();
    bit [9:0] ghr_F, ghr_X, pred_idx, upd_idx, gpc, gnx;
    scoreboard_not_applicable("phai ghim GHR va global_pht de co dinh chi muc gshare khi so hai duong doc");

    //---- A: cung pc, GHR khac -> entry khac --------------------------------
    // ghr PHAI force: chi muc gshare la pc_index^ghr; de RTL dich ghr thi entry
    // khao sat se troi.
    phase_of("A_index_is_pc_xor_ghr");
    bd.deposit_btb(64, 1'b1, 32'h0000_0140);
    bd.force_ghr(10'd0);
    bd.deposit_global_pht(64, `SNT);
    drive_chk_global_pht(32'h0000_0100, 1'b1, 64, `WNT, "ghr=0 (chi muc 64^0)");
    bd.force_ghr(10'h020);
    bd.deposit_global_pht(96, `SNT);
    drive_chk_global_pht(32'h0000_0100, 1'b1, 96, `WNT, "ghr=0x20, CUNG pc (chi muc 64^0x20)");

    //---- B: hai chi muc pc / nxpc2 trong CUNG mot chu ky -------------------
    phase_of("B_pc_vs_nxpc2_index_same_cycle");
    bd.force_ghr(10'h0A5);
    bd.force_predict_inputs(.pc(32'h0000_0100), .nxpc(NEU_NXPC), .fetch_opcode(OPC_NOP),
                            .branch_target_fetch(32'h0), .flush_in(2'b00), .halt(1'b0),
                            .nxpc2(32'h0000_0300));
    #2ns;
    gpc = rd_reg("global_pc_index");
    gnx = rd_reg("global_nxpc2_index");
    chk(gpc === (10'd64  ^ 10'h0A5), $sformatf("global_pc_index=0x%03h, ky vong 0x%03h (64 XOR ghr)", gpc, (10'd64 ^ 10'h0A5)));
    chk(gnx === (10'd192 ^ 10'h0A5), $sformatf("global_nxpc2_index=0x%03h, ky vong 0x%03h (192 XOR ghr)", gnx, (10'd192 ^ 10'h0A5)));
    chk(gpc !== gnx, "hai chi muc gshare BANG nhau -- khong tach duoc duong du doan va duong cap nhat");
    bd.release_predict_inputs();
    bd.release_ghr();

    //---- C: DO LECH chi muc giua luc du doan F va luc cap nhat F+2 (N2) ----
    // Chuoi 5 nhanh sat nhau P0..P4, deu TAKEN. ghr doc ngay sau push = gia tri
    // DANG dung trong chu ky do.
    phase_of("C_predict_vs_update_index_skew");
    h.reset_pipe();
    h.push_branch(.pc(32'h0000_0800), .taken(1'b1));   // P0
    h.push_branch(.pc(32'h0000_0900), .taken(1'b1));   // P1
    h.push_branch(.pc(32'h0000_0A00), .taken(1'b1),    // P2 -- nhanh quan tam
                  .ovr_nxpc2(1'b1), .nxpc2(32'h0000_0A00));
    ghr_F = bd.read_ghr();                             // GHR trong chu ky F cua P2
    h.push_branch(.pc(32'h0000_0B00), .taken(1'b1));   // P3
    h.push_branch(.pc(32'h0000_0C00), .taken(1'b1));   // P4
    ghr_X = bd.read_ghr();                             // GHR trong chu ky F+2 cua P2
    h.drain();
    pred_idx = 10'd640 ^ ghr_F;   // 0xA00 >> 2 = 640 ; doc du doan tai nxpc2
    upd_idx  = 10'd640 ^ ghr_X;   // cung dia chi, cap nhat tai F+2
    note($sformatf("N2: ghr(F)=0x%03h -> chi muc du doan=%0d ; ghr(F+2)=0x%03h -> chi muc cap nhat=%0d",
                   ghr_F, pred_idx, ghr_X, upd_idx));
    chk(ghr_X === {ghr_F[7:0], 2'b11},
        $sformatf("ghr(F+2)=0x%03h, ky vong 0x%03h (dich 2 lan, hai nhanh taken)", ghr_X, {ghr_F[7:0], 2'b11}));
    chk(pred_idx !== upd_idx,
        $sformatf("chi muc du doan = chi muc cap nhat = %0d -- khong dung duoc do lech N2", pred_idx));
  endtask
endclass : gshare_index_and_skew_test


//==============================================================================
// 5.2 global_pht_counter_and_init
//
// Sheet -- Flow: ep GHR co dinh; phat nhanh dau tien tai pc chua tung gap, sau
//   do lap lai de tao BTB hit; tiep tuc bang chuoi taken/not-taken phu moi
//   chuyen trang thai.
// Sheet -- Pass: lan gap dau PHT = WT; cac lan sau bo dem theo dung
//   SNT-WNT-WT-ST va bao hoa o hai dau.
// RTL Ref: bpu_predictor.v
//==============================================================================
class global_pht_counter_and_init_test extends bpu_scene_base;
  `bpu_test_utils(global_pht_counter_and_init_test, "5.2")

  localparam bit [31:0] PC = 32'h0000_0100;   // idx 64

  virtual task test_body();
    // ghr=0 co dinh -> chi muc = 64 xuyen suot. Phai force (moi nhanh dich GHR).
    bd.force_ghr(10'd0);

    phase_of("A_init_WT_on_miss");
    bd.deposit_btb(64, 1'b0, 32'h0);
    drive_chk_global_pht(PC, 1'b0, 64, `WT, "lan gap dau (bat ke taken)");

    phase_of("B_update_on_hit");
    drive_chk_global_pht(PC, 1'b0, 64, `WNT, "lan gap hai");

    phase_of("C_all_transitions_and_saturation");
    bd.deposit_btb(64, 1'b1, 32'h0000_0140);
    bd.deposit_global_pht(64, `SNT);
    drive_chk_global_pht(PC, 1'b1, 64, `WNT, "len 1: SNT->WNT");
    drive_chk_global_pht(PC, 1'b1, 64, `WT,  "len 2: WNT->WT");
    drive_chk_global_pht(PC, 1'b1, 64, `ST,  "len 3: WT->ST");
    drive_chk_global_pht(PC, 1'b1, 64, `ST,  "bao hoa tren: ST->ST");
    drive_chk_global_pht(PC, 1'b0, 64, `WT,  "xuong 1: ST->WT");
    drive_chk_global_pht(PC, 1'b0, 64, `WNT, "xuong 2: WT->WNT");
    drive_chk_global_pht(PC, 1'b0, 64, `SNT, "xuong 3: WNT->SNT");
    drive_chk_global_pht(PC, 1'b0, 64, `SNT, "bao hoa duoi: SNT->SNT");
    bd.release_ghr();
  endtask
endclass : global_pht_counter_and_init_test


//==============================================================================
// 5.3 gshare_aliasing
//
// Sheet -- Pass: lan ghi dung GHR CU lam chi muc; hai cap (pc, ghr) khac nhau
//   co cung XOR thi gop vao cung mot entry.
// RTL Ref: bpu_reg.v
//==============================================================================
class gshare_aliasing_test extends bpu_scene_base;
  `bpu_test_utils(gshare_aliasing_test, "5.3")

  virtual task test_body();
    //---- A: lan ghi dung GHR CU lam chi muc --------------------------------
    // ghr=5 (deposit, de tu do dich); miss -> entry 64^5=69 nhan WT. ghr dich
    // 5 -> 11; entry 64^11=75 phai con nguyen.
    phase_of("A_write_uses_old_ghr");
    bd.deposit_btb(64, 1'b0, 32'h0);
    bd.deposit_ghr(10'd5);
    drive_branch(32'h0000_0100, 1'b1);
    chk(bd.read_global_pht(69) === `WT,  $sformatf("global_pht[69]=2'b%02b, ky vong WT (ghr CU=5 -> 64^5)", bd.read_global_pht(69)));
    chk(bd.read_global_pht(75) === `SNT, $sformatf("global_pht[75]=2'b%02b, ky vong SNT (ghr MOI=11 KHONG duoc ghi)", bd.read_global_pht(75)));

    //---- B: XOR aliasing: (pc=0x100,ghr=0) va (pc=0x180,ghr=32) -> entry 64 -
    // ghr FORCE o day: hai cap chi gop vao entry 64 neu ghr dung bang gia tri
    // neu tai canh cap nhat.
    phase_of("B_xor_aliasing");
    bd.deposit_global_pht(64, `SNT);
    bd.force_ghr(10'd0);
    bd.deposit_btb(64, 1'b1, 32'h0140);
    drive_chk_global_pht(32'h0000_0100, 1'b1, 64, `WNT, "alias-1 (pc=0x100, ghr=0)");
    bd.force_ghr(10'd32);
    bd.deposit_btb(96, 1'b1, 32'h0240);
    drive_chk_global_pht(32'h0000_0180, 1'b1, 64, `WT, "alias-2 (pc=0x180, ghr=32 -> 96^32 = 64, CUNG entry)");
    bd.release_ghr();
  endtask
endclass : gshare_aliasing_test


//==============================================================================
// 5.4 global_pht_rw_all
//
// Sheet -- Pass: du 1024 entry: dinh dia chi toi duoc chi muc thap/giua/cao
//   qua pc/ghr, va moi entry giu gia tri rieng (doc lap luu tru).
// RTL Ref: bpu_reg.v
//==============================================================================
class global_pht_rw_all_test extends bpu_scene_base;
  `bpu_test_utils(global_pht_rw_all_test, "5.4")

  // ghr FORCE suot drive_branch: chi muc ghi la pc_index^ghr, neu de RTL dich
  // ghr thi entry dang kiem se troi.
  local task automatic addr_check(bit [9:0] ghr_v, int idx);
    bd.force_ghr(ghr_v);
    bd.deposit_global_pht(idx, `SNT);
    drive_chk_global_pht(32'h0000_0100, 1'b1, idx,
                         `WNT, $sformatf("dinh dia chi ghr=%0d (chi muc khong toi duoc / bi cat bit)", ghr_v));
  endtask

  virtual task test_body();
    int n_bad = 0;
    bd.deposit_btb(64, 1'b1, 32'h0140);   // hit path (pc_idx=64)

    //---- A: dinh dia chi toi chi muc thap / giua / cao (du 10 bit) ---------
    phase_of("A_addressing");
    addr_check(10'd64,  0);     // 64^64  = 0
    addr_check(10'd576, 512);   // 64^576 = 512
    addr_check(10'd959, 1023);  // 64^959 = 1023
    bd.release_ghr();

    //---- B: doc lap luu tru (ghi roi doc lai trong 0 thoi gian) -----------
    phase_of("B_storage_independence");
    for (int i = 0; i < 1024; i++) bd.deposit_global_pht(i, i[1:0]);
    for (int i = 0; i < 1024; i++)
      if (bd.read_global_pht(i) !== i[1:0])
        sweep_bad(n_bad, $sformatf("luu tru: pht[%0d]=2'b%02b, ky vong 2'b%02b", i, bd.read_global_pht(i), i[1:0]));
    sweep_report("doc lap luu tru 1024 entry", n_bad, 1024);
  endtask
endclass : global_pht_rw_all_test
