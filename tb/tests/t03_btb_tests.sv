//------------------------------------------------------------------------------
// FILE: tests/t03_btb_tests.sv -- Nhom 3: BTB
//   3.1 btb_write_and_target
//   3.2 btb_read_triple_port
//   3.3 btb_rw_all
//------------------------------------------------------------------------------


//==============================================================================
// 3.1 btb_write_and_target
//
// Sheet -- Flow: ghi mot entry roi ghi de bang offset khac; chay 100 chu ky
//   voi is_branch=0; quet bon loai offset (tien, lui, bang 0, tran 32 bit cho
//   dich bang 0); ghi hai PC trung pc[11:2] voi offset khac nhau.
// Sheet -- Pass: is_branch=1 -> btb_target = pc + branch_offset va btb_valid=1
//   trong ca bon loai offset, ke ca dich 32'h0. is_branch=0 -> khong ghi.
//   PC trung chi muc -> lan ghi sau thang.
// RTL Ref: bpu_predictor.v ; bpu_reg.v
//==============================================================================
class btb_write_and_target_test extends bpu_scene_base;
  `bpu_test_utils(btb_write_and_target_test, "3.1")

  // Mot nhanh taken tai pc roi kiem entry cua no.
  local task automatic write_and_chk(string lbl, bit [31:0] pc, bit [31:0] offset, bit [31:0] exp_tgt);
    int idx = bpu_idx(pc);
    drive_branch(pc, 1'b1, offset);
    chk(bd.read_btb_valid(idx) === 1'b1, $sformatf("%s: btb_valid[%0d] != 1", lbl, idx));
    chk(bd.read_btb_target(idx) === exp_tgt,
        $sformatf("%s: btb_target[%0d]=0x%08h, ky vong 0x%08h", lbl, idx, bd.read_btb_target(idx), exp_tgt));
  endtask

  virtual task test_body();
    //---- A: ghi roi ghi de tai cung mot PC ---------------------------------
    phase_of("A_write_overwrite");
    write_and_chk("lan ghi dau", 32'h0000_0100, 32'h40, 32'h0000_0140);
    write_and_chk("ghi de",      32'h0000_0100, 32'h80, 32'h0000_0180);

    //---- B: 100 chu ky is_branch=0 -> khong ghi ----------------------------
    phase_of("B_no_write_100cyc");
    idle_cycles(100);
    chk(bd.read_btb_valid(64)  === 1'b1, "btb_valid[64] bi xoa trong 100 chu ky nghi");
    chk(bd.read_btb_target(64) === 32'h0000_0180,
        $sformatf("btb_target[64]=0x%08h doi trong luc nghi, ky vong giu 0x180", bd.read_btb_target(64)));
    chk(bd.read_btb_valid(1000) === 1'b0, "btb_valid[1000] != 0: chu ky nghi da ghi nham entry");

    //---- C: bon loai offset ------------------------------------------------
    phase_of("C_four_offset_kinds");
    write_and_chk("offset tien",   32'h0000_0200, 32'h0000_0040, 32'h0000_0240);
    write_and_chk("offset lui",    32'h0000_0300, 32'hFFFF_FFC0, 32'h0000_02C0);
    write_and_chk("offset 0",      32'h0000_0600, 32'h0000_0000, 32'h0000_0600);
    write_and_chk("offset tran -> dich 0 VAN hop le", 32'h0000_0400, 32'hFFFF_FC00, 32'h0000_0000);

    //---- D: hai PC trung chi muc pc[11:2] -> lan ghi sau thang -------------
    phase_of("D_index_alias");
    write_and_chk("alias buoc 1", 32'h0000_0100, 32'h40, 32'h0000_0140);
    write_and_chk("alias buoc 2 (0x1100 cung idx 64)", 32'h0000_1100, 32'h80, 32'h0000_1180);
  endtask
endclass : btb_write_and_target_test


//==============================================================================
// 3.2 btb_read_triple_port
//
// Sheet -- Flow: nap truoc cac entry; dat pc, nxpc va nxpc2 tro ba chi muc
//   khac nhau trong cung mot chu ky; doc truoc va sau canh len clk; cho dia chi
//   da ghi xuat hien lai o nxpc2.
// Sheet -- Pass: btb_valid doc doc lap tai pc, nxpc va nxpc2, cap nhat to hop
//   tuc thi; btb_target chi co o pc va nxpc2 (KHONG ton tai btb_target_nxpc);
//   doc trong luc ghi tra ve gia tri cu; cong nxpc2 doc dung target da luu.
// RTL Ref: bpu_reg.v
//
// btb_valid_* / btb_target_* la to hop THUAN tu dia chi dang lai, khong phu
// thuoc carry-down, nen doc truc tiep ngay sau apply() la hop le.
//==============================================================================
class btb_read_triple_port_test extends bpu_scene_base;
  `bpu_test_utils(btb_read_triple_port_test, "3.2")

  localparam bit [31:0] T64  = 32'h0000_0140;
  localparam bit [31:0] T192 = 32'h0000_0340;

  virtual task test_body();
    uvm_hdl_data_t dummy;

    // Huan luyen MOT LAN qua duong cap nhat THAT (reference bam sat):
    //   0x100 (idx 64 ) : 24 nhanh taken -> target 0x140, du doan T tai nxpc2
    //   0x300 (idx 192) : 1 nhanh taken  -> target 0x340
    //   0x200 (idx 128) : KHONG cham     -> btb_valid = 0
    train_predict_taken(32'h0000_0100, 24);
    drive_branch(32'h0000_0300, 1'b1, 32'h40);

    //---- A: ba cong doc doc lap trong CUNG mot chu ky ----------------------
    phase_of("A_three_ports_independent");
    chk(bd.read_btb_valid(64)  === 1'b1, "chuan bi: btb_valid[64] phai = 1");
    chk(bd.read_btb_valid(128) === 1'b0, "chuan bi: btb_valid[128] phai = 0");
    chk(bd.read_btb_valid(192) === 1'b1, "chuan bi: btb_valid[192] phai = 1");
    apply(.pc(32'h0000_0100), .nxpc(32'h0000_0200), .nxpc2(32'h0000_0300), .opcode(OPC_NOP));
    chk(bd.read_btb_valid_pc_port() === 1'b1, "btb_valid_pc != 1 (idx 64 hop le)");
    chk(bd.read_btb_valid_nxpc()    === 1'b0, "btb_valid_nxpc != 0 (idx 128 khong hop le)");
    chk(bd.read_btb_valid_nxpc2()   === 1'b1, "btb_valid_nxpc2 != 1 (idx 192 hop le)");
    chk(bd.read_btb_target_pc_port() === T64,
        $sformatf("btb_target_pc=0x%08h, ky vong 0x%08h", bd.read_btb_target_pc_port(), T64));
    chk(bd.read_btb_target_nxpc2() === T192,
        $sformatf("btb_target_nxpc2=0x%08h, ky vong 0x%08h", bd.read_btb_target_nxpc2(), T192));
    // Doi cho ba dia chi -> ba cong doi theo TUC THI (to hop)
    apply(.pc(32'h0000_0200), .nxpc(32'h0000_0300), .nxpc2(32'h0000_0100), .opcode(OPC_NOP));
    chk(bd.read_btb_valid_pc_port() === 1'b0, "doi dia chi: btb_valid_pc khong cap nhat to hop");
    chk(bd.read_btb_valid_nxpc()    === 1'b1, "doi dia chi: btb_valid_nxpc khong cap nhat to hop");
    chk(bd.read_btb_valid_nxpc2()   === 1'b1, "doi dia chi: btb_valid_nxpc2 khong cap nhat to hop");
    chk(bd.read_btb_target_nxpc2()  === T64,
        $sformatf("btb_target_nxpc2=0x%08h sau khi doi dia chi, ky vong 0x%08h", bd.read_btb_target_nxpc2(), T64));

    //---- B: KHONG ton tai btb_target_nxpc (kiem cau truc) ------------------
    // uvm_hdl_read tren duong dan khong ton tai tu phat UVM/DPI/NOBJ1 -- o day
    // "khong doc duoc" la KET QUA MONG DOI, nen ha rieng id do xuong INFO.
    phase_of("B_no_btb_target_nxpc");
    uvm_top.set_report_severity_id_override(UVM_ERROR, "UVM/DPI/NOBJ1", UVM_INFO);
    chk(uvm_hdl_read("bpu_hw_top.dut.btb_target_nxpc", dummy) === 0,
        "doc duoc bpu_hw_top.dut.btb_target_nxpc -- RTL hybrid KHONG duoc co cong nay");
    uvm_top.set_report_severity_id_override(UVM_ERROR, "UVM/DPI/NOBJ1", UVM_ERROR);

    //---- C: doc trong luc ghi tra ve gia tri CU ----------------------------
    // is_branch bat DUNG MOT chu ky, neu giu lau hon se lam hong trang thai da
    // huan luyen.
    phase_of("C_read_during_write");
    apply(.pc(32'h0000_0100), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .is_branch(1'b1), .taken(1'b1), .offset(32'h80));
    chk(bd.read_btb_target(64) === T64,
        $sformatf("read-during-write: btb_target[64]=0x%08h, ky vong 0x%08h (khong write-through)", bd.read_btb_target(64), T64));
    apply(.pc(32'h0000_0100), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP));   // 1 canh len da qua
    chk(bd.read_btb_target(64) === 32'h0000_0180,
        $sformatf("write-after-clk: btb_target[64]=0x%08h, ky vong 0x180 (pc+offset)", bd.read_btb_target(64)));

    //---- D: nhan lai nhanh vong lap QUA CONG NXPC2 -------------------------
    // Cong nxpc2 phai doc target MOI NHAT (0x180) va bit du doan = T -> f_valid.
    phase_of("D_loop_revisit_via_nxpc2");
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(32'h0000_0100), .opcode(OPC_NOP));
    chk(bd.read_btb_valid_nxpc2()    === 1'b1, "vong lap: btb_valid_nxpc2 != 1");
    chk(bd.read_btb_target_nxpc2()   === 32'h0000_0180,
        $sformatf("vong lap: btb_target_nxpc2=0x%08h, ky vong 0x180 (target moi nhat)", bd.read_btb_target_nxpc2()));
    chk(bd.read_predict_taken_nxpc2() === 1'b1, "vong lap: predict_taken_nxpc2 != 1");
    chk(bd.read_bpu_nxpc2_valid() === 1'b1, "vong lap: bpu_nxpc2_valid != 1 (f_valid khong tich cuc)");
    chk(bd.read_bpu_nxpc2() === 32'h0000_0180,
        $sformatf("vong lap: bpu_nxpc2=0x%08h, ky vong 0x180 (= btb_target_nxpc2)", bd.read_bpu_nxpc2()));
    bus_free();
  endtask
endclass : btb_read_triple_port_test


//==============================================================================
// 3.3 btb_rw_all
//
// Sheet -- Flow: lap i = 0..1023: ghi tai pc = i<<2 voi offset = i, sau do doc
//   lai toan bo entry.
// Sheet -- Pass: moi entry giu dung target da ghi; khong entry nao bi ghi de.
// RTL Ref: bpu_reg.v
//
// LECH NHO SO VOI SHEET: offset la (i<<1) thay vi i, vi branch_offset la
// immediate B-type luon can chan 2 byte (bpu_item.sv ep bit0 = 0). (i<<1) van
// cho moi entry mot target rieng biet.
//==============================================================================
class btb_rw_all_test extends bpu_scene_base;
  `bpu_test_utils(btb_rw_all_test, "3.3")

  virtual task test_body();
    int n_bad_valid = 0, n_bad_target = 0;
    bit [31:0] exp;

    phase_of("A_write_1024");
    for (int i = 0; i < 1024; i++) drive_branch(i << 2, 1'b1, i << 1);

    phase_of("B_sweep_1024");
    for (int i = 0; i < 1024; i++) begin
      exp = (i << 2) + (i << 1);          // target = pc + offset
      if (bd.read_btb_valid(i) !== 1'b1)
        sweep_bad(n_bad_valid, $sformatf("btb_valid[%0d] != 1", i));
      if (bd.read_btb_target(i) !== exp)
        sweep_bad(n_bad_target, $sformatf("btb_target[%0d]=0x%08h, ky vong 0x%08h", i, bd.read_btb_target(i), exp));
    end
    sweep_report("btb_valid  1024 entry", n_bad_valid,  1024);
    sweep_report("btb_target 1024 entry", n_bad_target, 1024);
  endtask
endclass : btb_rw_all_test
