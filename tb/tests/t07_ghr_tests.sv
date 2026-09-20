//------------------------------------------------------------------------------
// FILE: tests/t07_ghr_tests.sv -- Nhom 7: GHR
//   7.1 ghr_shift_gate_shared
//------------------------------------------------------------------------------


//==============================================================================
// 7.1 ghr_shift_gate_shared
//
// Sheet -- Flow: Pha A: mau phuc tap, roi chuoi toan taken va toan not-taken de
//   cham hai bien. Pha B: 20 chu ky khong nhanh, roi nhanh voi btb_valid_pc=0
//   va =1. Pha C: nhanh tai nhieu PC khac nhau, quan sat GHR theo thu tu.
// Sheet -- Pass: GHR dich trai, chen branch_taken vao bit[0]; bit[9] bi day ra
//   sau 10 lan dich; dat 10'h000 va 10'h3FF. GHR giu khi is_branch=0, dich khi
//   is_branch=1 bat ke branch_taken hay btb_valid_pc. Moi PC dung chung GHR.
// RTL Ref: bpu_predictor.v ; bpu_reg.v
//==============================================================================
class ghr_shift_gate_shared_test extends bpu_scene_base;
  `bpu_test_utils(ghr_shift_gate_shared_test, "7.1")

  local function void chk_ghr(bit [9:0] exp, string lbl);
    chk(bd.read_ghr() === exp, $sformatf("ghr=0x%03h, ky vong 0x%03h (%s)", bd.read_ghr(), exp, lbl));
  endfunction

  virtual task test_body();
    bit pat[14]  = '{1'b1,1'b1,1'b1,1'b1, 1'b1,1'b0,1'b1,1'b1,1'b0,1'b0,1'b1,1'b0,1'b1,1'b0};
    bit tseq[10] = '{1'b1,1'b0,1'b1,1'b1,1'b0,1'b0,1'b1,1'b0,1'b1,1'b1};

    //---- A1: dich trai, chen bit[0], sau 10 lan day bit[9] ra --------------
    phase_of("A1_shift_depth10");
    foreach (pat[k]) drive_branch(32'h0000_0100, pat[k]);   // 4 bit dau bi day ra
    chk_ghr(10'h2CA, "10 bit cuoi theo thu tu dich");

    //---- A2: cham hai bien 10'h3FF va 10'h000 -----------------------------
    phase_of("A2_both_boundaries");
    repeat (10) drive_branch(32'h0000_0100, 1'b1);
    chk_ghr(10'h3FF, "bien tren sau 10 nhanh taken");
    repeat (10) drive_branch(32'h0000_0100, 1'b0);
    chk_ghr(10'h000, "bien duoi sau 10 nhanh not-taken");

    //---- B1: giu nguyen khi is_branch=0 -----------------------------------
    phase_of("B1_hold_on_non_branch");
    drive_branch(32'h0000_0100, 1'b1);
    chk_ghr(10'h001, "truoc khi nghi");
    idle_cycles(20);
    chk_ghr(10'h001, "GIU sau 20 chu ky khong nhanh");

    //---- B2: dich khong phu thuoc btb_valid_pc VA branch_taken ------------
    phase_of("B2_shift_independent_of_btb_and_taken");
    chk(bd.read_btb_valid(192) === 1'b0, "chuan bi: btb_valid[192] phai = 0");
    drive_branch(32'h0000_0300, 1'b0);            // BTB miss + not-taken
    chk_ghr(10'h002, "van dich du BTB miss va not-taken");
    chk(bd.read_btb_valid(192) === 1'b1, "sau nhanh: btb_valid[192] phai = 1");
    drive_branch(32'h0000_0300, 1'b0);            // BTB hit + not-taken
    chk_ghr(10'h004, "dich khi BTB hit");
    drive_branch(32'h0000_0300, 1'b1);            // BTB hit + taken
    chk_ghr(10'h009, "dich khi BTB hit + taken");

    //---- C: GHR dung chung cho moi PC -- chi phu thuoc THU TU THOI GIAN ----
    phase_of("C_shared_across_pcs");
    repeat (10) drive_branch(32'h0000_0100, 1'b0);
    chk_ghr(10'h000, "chuan bi pha C");
    foreach (tseq[k]) drive_branch((k + 1) << 8, tseq[k]);   // 0x100, 0x200, ... 0xA00
    chk_ghr(10'h2CB, "thu tu thoi gian, doc lap PC");
  endtask
endclass : ghr_shift_gate_shared_test
