//------------------------------------------------------------------------------
// FILE: tests/t09_precompute_tests.sv -- Nhom 9: Pre-compute & Gating
//   9.1 precompute_gating_and_opcode_scope
//------------------------------------------------------------------------------


//==============================================================================
// 9.1 precompute_gating_and_opcode_scope
//
// Sheet -- Flow: quet du 128 fetch_opcode; quet flush_in qua {0,1,2,3}; giu
//   dieu kien tang fetch tich cuc (BTB hit tai nxpc2 va predict T) roi quan sat
//   f_valid va d_valid; theo tiep toi execute cho opcode khac BCC voi is_branch=0.
// Sheet -- Pass: fetch_is_branch=1 duy nhat tai 7'b1100011; fetch_ready=1 chi
//   voi flush_in {0,1}. flush_in {2,3}: f_valid = d_valid = 0. Opcode khac BCC:
//   d_valid=0 nhung f_valid VAN co the = 1 (f_valid khong kiem opcode); khi do
//   tai execute is_branch=0 nen bpu_flush=0 va corr_valid=0 (DesignNotes R1).
// RTL Ref: bpu_ctrl.v
//==============================================================================
class precompute_gating_and_opcode_scope_test extends bpu_scene_base;
  `bpu_test_utils(precompute_gating_and_opcode_scope_test, "9.1")

  localparam bit [31:0] FRESH_NXPC = 32'h0000_0B00;   // idx 704, chua bao gio duoc ghi

  // Hai chu ky voi tang fetch tich cuc (nxpc2 = TK), nxpc = dia chi chua ghi,
  // opcode/flush_in theo y; tra ve anh chup.
  local task automatic hold_and_snap(bit [6:0] opv, bit [1:0] fl, output bpu_fetch_obs_t o);
    repeat (2) apply(.pc(NEU_PC), .nxpc(FRESH_NXPC), .nxpc2(ADDR_TK), .opcode(opv),
                     .btf(32'h40), .flush_in(fl));
    o = snap();
  endtask

  virtual task test_body();
    bpu_fetch_obs_t o, oF, oD, oX;
    bit [31:0] exp_tgt;
    int        n_is_branch = 0;
    string     s;

    setup_addresses();
    exp_tgt = bd.read_btb_target(bpu_idx(ADDR_TK));
    chk(bd.read_btb_valid(bpu_idx(ADDR_TK))   === 1'b1, "chuan bi: btb_valid[TK] phai = 1");
    chk(bd.read_btb_valid(bpu_idx(FRESH_NXPC)) === 1'b0, "chuan bi: btb_valid tai nxpc phai = 0 thi backstop moi lai duoc");

    //---- A: quet du 128 gia tri fetch_opcode, tang fetch luon tich cuc ------
    phase_of("A_opcode_sweep_128");
    for (int op = 0; op < 128; op++) begin
      bit [6:0] opv = op[6:0];
      bit exp_fib = (opv === OPC_BR);
      hold_and_snap(opv, 2'd0, o);
      if (o.fib) n_is_branch++;
      chk(o.fib === exp_fib, $sformatf("opcode 0x%02h: fetch_is_branch=%0d, ky vong %0d", opv, o.fib, exp_fib));
      chk(o.dv  === exp_fib, $sformatf("opcode 0x%02h: d_valid=%0d, ky vong %0d (BTB truot tai nxpc, fetch_ready=1)", opv, o.dv, exp_fib));
      chk(o.fv  === 1'b1,    $sformatf("opcode 0x%02h: f_valid=%0d, ky vong 1 -- tang fetch KHONG kiem opcode (bpu_ctrl.v)", opv, o.fv));
    end
    chk(n_is_branch === 1, $sformatf("A: fetch_is_branch=1 tai %0d/128 opcode, ky vong dung 1 (chi 7'b1100011)", n_is_branch));
    note($sformatf("A: quet 128 opcode -- fetch_is_branch=1 dung %0d lan (tai 7'b1100011); f_valid=1 o CA 128 gia tri", n_is_branch));

    //---- B: quet du BON gia tri flush_in x hai opcode -----------------------
    // RTL xu ly 3 y het 2, nen 3 la ngo vao hop le phai phu.
    phase_of("B_flush_sweep_4");
    s = {"\n=== 9.1 PHAM VI CUA fetch_ready (bpu_ctrl.v) ===\n",
         "   flush_in  opcode  fetch_ready  f_valid  d_valid  bpu_nxpc2_valid\n",
         "   ---------------------------------------------------------------\n"};
    for (int fl = 0; fl < 4; fl++)
      for (int k = 0; k < 2; k++) begin
        bit [6:0] opv = (k == 0) ? OPC_BR : OPC_NOP;
        bit exp_fr = (fl == 0) || (fl == 1);
        bit exp_dv = exp_fr && (opv === OPC_BR);
        hold_and_snap(opv, fl[1:0], o);
        s = {s, $sformatf("      %0d      %s       %0d          %0d        %0d           %0d\n",
                          fl, (k == 0) ? "BCC " : "ADDI", o.fr, o.fv, o.dv, o.outv)};
        chk(o.fr === exp_fr, $sformatf("flush_in=%0d: fetch_ready=%0d, ky vong %0d", fl, o.fr, exp_fr));
        chk(o.fv === exp_fr, $sformatf("flush_in=%0d opcode=0x%02h: f_valid=%0d, ky vong %0d", fl, opv, o.fv, exp_fr));
        chk(o.dv === exp_dv, $sformatf("flush_in=%0d opcode=0x%02h: d_valid=%0d, ky vong %0d", fl, opv, o.dv, exp_dv));
        if (fl >= 2) begin
          chk(o.fv === 1'b0 && o.dv === 1'b0, $sformatf("flush_in=%0d: ky vong f_valid=d_valid=0, do duoc %0d/%0d", fl, o.fv, o.dv));
          chk(o.outv === 1'b0, $sformatf("flush_in=%0d: bpu_nxpc2_valid=%0d, ky vong 0", fl, o.outv));
        end
      end
    note({s, "   ---------------------------------------------------------------\n",
             "   flush_in = 3 duoc xu ly Y HET 2: ca hai deu cho fetch_ready = 0.\n",
             "======================================================="});

    //---- C: pham vi cua opcode -- R1 nhin tu phia CHUYEN HUONG --------------
    // Mot lenh KHONG PHAI nhanh di qua ba tang trong khi tang fetch doan re:
    //   F   : nxpc2 = TK (BTB trung + du doan re), opcode tai decode = ADDI
    //   F+1 : nxpc  = TK
    //   F+2 : pc    = TK, is_branch = 0
    phase_of("C_opcode_scope_to_execute");
    apply_idle(4);
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_TK), .opcode(OPC_NOP), .btf(32'h40));
    oF = snap();
    chk(oF.fib  === 1'b0, $sformatf("C(F): fetch_is_branch=%0d, ky vong 0 (opcode = ADDI)", oF.fib));
    chk(oF.dv   === 1'b0, $sformatf("C(F): d_valid=%0d, ky vong 0 (opcode khac BCC)", oF.dv));
    chk(oF.fv   === 1'b1, $sformatf("C(F): f_valid=%0d, ky vong 1 -- tang fetch KHONG kiem opcode", oF.fv));
    chk(oF.outv === 1'b1, $sformatf("C(F): bpu_nxpc2_valid=%0d, ky vong 1", oF.outv));
    chk(oF.outp === exp_tgt, $sformatf("C(F): bpu_nxpc2=0x%08h, ky vong 0x%08h (btb_target_nxpc2)", oF.outp, exp_tgt));
    apply(.pc(NEU_PC), .nxpc(ADDR_TK), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP), .btf(32'h40));
    oD = snap();
    chk(oD.dv === 1'b0, $sformatf("C(F+1): d_valid=%0d, ky vong 0", oD.dv));
    apply(.pc(ADDR_TK), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP), .is_branch(1'b0));
    oX = snap();
    note($sformatf({
      "\n=== 9.1 PHA C -- DesignNotes R1 nhin tu phia CHUYEN HUONG ===\n",
      "  Tang fetch da doan re cho mot lenh KHONG PHAI nhanh:\n",
      "    F   : fetch_is_branch=%0d  d_valid=%0d  f_valid=%0d  -> bpu_nxpc2_valid=%0d, bpu_nxpc2=0x%08h\n",
      "    F+2 : is_branch=0 tai execute -> predicted_taken=%0d  bpu_flush=%0d  corr_valid=%0d\n",
      "  Ket luan: bpu_ctrl.v KHONG kiem opcode, nen tang fetch chuyen huong duoc cho\n",
      "  moi lenh co BTB trung tai nxpc2. Tang execute KHONG the sua sai do, vi ca\n",
      "  bpu_flush lan corr_valid deu bi is_branch=0 chan lai. Chi mot truong tag o\n",
      "  BTB moi tranh duoc -- thu ma BTB hien khong co.\n",
      "======================================================="},
      oF.fib, oF.dv, oF.fv, oF.outv, oF.outp, bd.read_predicted_taken(), oX.fl, oX.cv));
    chk(bd.read_predicted_taken() === 1'b1, $sformatf("C(F+2): predicted_taken=%0d, ky vong 1 -- quyet dinh cua tang fetch phai xuong toi execute", bd.read_predicted_taken()));
    chk(oX.fl   === 2'd0, $sformatf("C(F+2): bpu_flush=%0d, ky vong 0 (is_branch=0 chan bpu_ctrl.v)", oX.fl));
    chk(oX.cv   === 1'b0, $sformatf("C(F+2): corr_valid=%0d, ky vong 0 (is_branch=0 chan bpu_ctrl.v)", oX.cv));
    chk(oX.outv === 1'b0, $sformatf("C(F+2): bpu_nxpc2_valid=%0d, ky vong 0", oX.outv));
    bus_free();
  endtask
endclass : precompute_gating_and_opcode_scope_test
