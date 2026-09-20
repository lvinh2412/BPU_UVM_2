//------------------------------------------------------------------------------
// FILE: tests/t02_halt_tests.sv -- Nhom 2: Halt
//   2.1 halt_block_and_resume
//   2.2 halt_carry_freeze
//------------------------------------------------------------------------------


//==============================================================================
// 2.1 halt_block_and_resume
//
// Sheet -- Flow: nap truoc trang thai; phat nhanh sao cho moi wr_en deu tich
//   cuc; giu halt=1 trong 100 chu ky dong thoi thay doi pc/nxpc/nxpc2; sau do
//   nha halt trong mot chu ky va quan sat.
// Sheet -- Pass: trong luc halt sau bang giu nguyen; cac ngo ra to hop
//   (btb_target_pc, predict_taken_nxpc2, bpu_nxpc2, bpu_flush) van doi theo ngo
//   vao. Sau khi nha: BTB ghi target, PHT cap nhat, GHR dich o chu ky ke tiep.
// RTL Ref: bpu_reg.v ; bpu_ctrl.v
//==============================================================================
class halt_block_and_resume_test extends bpu_scene_base;
  `bpu_test_utils(halt_block_and_resume_test, "2.1")

  localparam int N_HALT = 100;

  // Mot chu ky halt=1, is_branch=0, nxpc2/pc theo y -> doc duong to hop.
  local task automatic halted_read(bit [31:0] pc, bit [31:0] nxpc2);
    apply(.pc(pc), .nxpc(NEU_NXPC), .nxpc2(nxpc2), .opcode(OPC_NOP), .halt(1'b1));
  endtask

  virtual task test_body();
    bpu_fetch_obs_t o_tk, o_nt, o_ut, o;
    bit [11:0] lidx, bh0;
    int        gidx, diffs;
    bit [1:0]  lp0, gp0, ch0, exp_lp, exp_gp;
    bit [31:0] bt0;
    bit [9:0]  ghr0;
    bit [31:0] pcs[4];

    //---- A: nap truoc trang thai --------------------------------------------
    phase_of("A_preload");
    setup_addresses();
    lidx = bd.read_local_bht(bpu_idx(ADDR_TK));
    gidx = bpu_idx(ADDR_TK) ^ bd.read_ghr();
    bt0  = bd.read_btb_target(bpu_idx(ADDR_TK));
    bh0  = bd.read_local_bht(bpu_idx(ADDR_TK));
    lp0  = bd.read_local_pht(lidx);
    gp0  = bd.read_global_pht(gidx);
    ch0  = bd.read_choice(bpu_idx(ADDR_TK));
    ghr0 = bd.read_ghr();
    chk(bd.read_btb_valid(bpu_idx(ADDR_TK)) === 1'b1, "A: btb_valid[TK] phai = 1 sau khi nap");
    note($sformatf("A nap xong: btb_target[TK]=0x%08h bht[TK]=0x%03h local_pht[0x%03h]=%02b global_pht[%0d]=%02b choice[TK]=%02b ghr=0x%03h",
                   bt0, bh0, lidx, lp0, gidx, gp0, ch0, ghr0));

    //---- B: dua carry-down vao trang thai BAT DONG de choice_wr_en tich cuc --
    // choice_wr_en = disagree && is_branch && btb_valid_pc; tai ADDR_TK local[1]=1
    // con global[1]=0 => disagree = 1 khi halt o pha C.
    phase_of("B_arm_choice_write_enable");
    observe_at(ADDR_TK, 2'd0, o_tk);
    show_fetch("B doc tai ADDR_TK", ADDR_TK, o_tk);
    chk(o_tk.lp[1] !== o_tk.gp[1],
        $sformatf("B: local[1]=%0d va global[1]=%0d phai KHAC nhau thi choice_wr_en moi tich cuc duoc", o_tk.lp[1], o_tk.gp[1]));
    repeat (2) apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_TK), .opcode(OPC_NOP));
    chk(bd.read_local_carry() !== bd.read_global_carry(),
        $sformatf("B: local_carry=%0d global_carry=%0d -- can khac nhau de choice_wr_en tich cuc",
                  bd.read_local_carry(), bd.read_global_carry()));
    snapshot_state();

    //---- C: halt = 1 trong 100 chu ky, moi wr_en tich cuc, dia chi doi lien tuc
    phase_of("C_halt_100_cycles");
    pcs = '{ADDR_TK, ADDR_NT, ADDR_UT, 32'h0000_0900};
    for (int k = 0; k < N_HALT; k++)
      apply(.pc(pcs[k % 4]), .nxpc(pcs[(k+1) % 4]), .nxpc2(pcs[(k+2) % 4]),
            .opcode(OPC_BR), .btf(32'h40 + k), .halt(1'b1),
            .is_branch(1'b1), .taken(k[0]), .offset(32'h80 + k));
    diffs = compare_state("C sau 100 chu ky halt");
    note($sformatf("C: %0d chu ky halt=1 voi is_branch=1 va pc/nxpc/nxpc2/offset/taken doi lien tuc -> %0d o trang thai bi doi (ky vong 0)", N_HALT, diffs));

    //---- D: trong luc halt, duong DOC to hop van chay ------------------------
    phase_of("D_combinational_reads_under_halt");
    // (1) btb_target_pc / btb_valid_pc bam theo pc
    halted_read(ADDR_TK, NEU_NXPC2);
    chk(bd.read_btb_target_pc_port() === bt0,
        $sformatf("D: halt=1, pc=ADDR_TK -> btb_target_pc=0x%08h, ky vong 0x%08h", bd.read_btb_target_pc_port(), bt0));
    chk(bd.read_btb_valid_pc_port() === 1'b1, "D: halt=1, pc=ADDR_TK -> btb_valid_pc phai = 1");
    halted_read(ADDR_UT, NEU_NXPC2);
    chk(bd.read_btb_valid_pc_port() === 1'b0,
        "D: halt=1, pc=ADDR_UT (chua ghi) -> btb_valid_pc phai = 0; duong doc BTB da chet trong luc halt");
    // (2) predict_taken_nxpc2 / bpu_nxpc2 bam theo nxpc2
    observe_at(ADDR_TK, 2'd0, o_tk);
    halted_read(NEU_PC, ADDR_TK);  o = snap();
    chk(o.pt === 1'b1 && o.hit === 1'b1,
        $sformatf("D: halt=1, nxpc2=ADDR_TK -> hit=%0d predT=%0d, ky vong 1/1", o.hit, o.pt));
    chk(o.outv === 1'b1 && o.outp === bt0,
        $sformatf("D: halt=1 -> bpu_nxpc2_valid=%0d bpu_nxpc2=0x%08h, ky vong 1 / 0x%08h", o.outv, o.outp, bt0));
    halted_read(NEU_PC, ADDR_NT);  o_nt = snap();
    chk(o_nt.pt === 1'b0 && o_nt.hit === 1'b1,
        $sformatf("D: halt=1, nxpc2=ADDR_NT -> hit=%0d predT=%0d, ky vong 1/0", o_nt.hit, o_nt.pt));
    chk(o_nt.outv === 1'b0,
        $sformatf("D: halt=1, nxpc2=ADDR_NT -> bpu_nxpc2_valid=%0d, ky vong 0 (du doan khong re)", o_nt.outv));
    halted_read(NEU_PC, ADDR_UT);  o_ut = snap();
    chk(o_ut.hit === 1'b0, $sformatf("D: halt=1, nxpc2=ADDR_UT -> btb_valid_nxpc2=%0d, ky vong 0", o_ut.hit));
    // (3) bpu_flush van doi theo branch_taken cua tang execute
    apply(.pc(ADDR_TK), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .halt(1'b1), .is_branch(1'b1), .taken(1'b1), .offset(32'h40));
    o = snap();
    apply(.pc(ADDR_TK), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .halt(1'b1), .is_branch(1'b1), .taken(1'b0), .offset(32'h40));
    o_nt = snap();
    note($sformatf("D: halt=1, pred_was_hit=%0d predicted_taken=%0d -> branch_taken=1 cho bpu_flush=%0d, branch_taken=0 cho bpu_flush=%0d",
                   bd.read_pred_was_hit(), bd.read_predicted_taken(), o.fl, o_nt.fl));
    chk(o.fl !== o_nt.fl,
        $sformatf("D: bpu_flush khong doi theo branch_taken trong luc halt (%0d va %0d) -- duong to hop cua tang execute phai song", o.fl, o_nt.fl));
    diffs = compare_state("D sau cac phep doc to hop");
    chk(diffs == 0, "D: doc to hop trong luc halt da lam doi trang thai");

    //---- E: nha halt DUNG MOT chu ky -> ghi phuc hoi ngay o chu ky ke --------
    // taken=0 co chu y: local_pht[0xFFF] dang o ST, nhanh re nua se giu ST (bao
    // hoa) va phep kiem "PHT co cap nhat khong" mat y nghia; taken=0 thi ST -> WT.
    phase_of("E_resume_next_cycle");
    exp_lp = bpu_upd_ctr(lp0, 1'b0);
    exp_gp = bpu_upd_ctr(gp0, 1'b0);
    apply(.pc(ADDR_TK), .nxpc(NEU_NXPC), .nxpc2(ADDR_TK), .opcode(OPC_NOP),
          .halt(1'b0), .is_branch(1'b1), .taken(1'b0), .offset(32'h00C0));
    halted_read(NEU_PC, NEU_NXPC2);          // tro lai halt=1: chi DUNG mot lan ghi
    chk(bd.read_btb_target(bpu_idx(ADDR_TK)) === (ADDR_TK + 32'h00C0),
        $sformatf("E: btb_target[TK]=0x%08h sau khi nha halt, ky vong 0x%08h", bd.read_btb_target(bpu_idx(ADDR_TK)), ADDR_TK + 32'h00C0));
    chk(bd.read_local_bht(bpu_idx(ADDR_TK)) === {bh0[10:0], 1'b0},
        $sformatf("E: local_bht[TK]=0x%03h sau khi nha halt, ky vong 0x%03h (dich trai + 0)", bd.read_local_bht(bpu_idx(ADDR_TK)), {bh0[10:0], 1'b0}));
    chk(bd.read_ghr() === {ghr0[8:0], 1'b0},
        $sformatf("E: ghr=0x%03h sau khi nha halt, ky vong 0x%03h (dich trai + 0)", bd.read_ghr(), {ghr0[8:0], 1'b0}));
    chk(bd.read_local_pht(lidx) === exp_lp,
        $sformatf("E: local_pht[0x%03h]=%02b sau khi nha halt, ky vong %02b (bo dem tu %02b, taken=0)", lidx, bd.read_local_pht(lidx), exp_lp, lp0));
    chk(exp_lp !== lp0, "E: bo dem local_pht dang o dau day nen phep kiem cap nhat se vacuous -- doi trang thai nap truoc");
    chk(bd.read_global_pht(gidx) === exp_gp,
        $sformatf("E: global_pht[%0d]=%02b sau khi nha halt, ky vong %02b (bo dem tu %02b, taken=0)", gidx, bd.read_global_pht(gidx), exp_gp, gp0));
    note($sformatf({
      "\n=== 2.1 nha halt: ghi phuc hoi NGAY o chu ky ke ===\n",
      "  btb_target[TK]   : 0x%08h -> 0x%08h\n",
      "  local_bht[TK]    : 0x%03h      -> 0x%03h\n",
      "  ghr              : 0x%03h      -> 0x%03h\n",
      "  local_pht[0x%03h]  : %02b        -> %02b\n",
      "  global_pht[%4d]  : %02b        -> %02b\n",
      "==================================================="},
      bt0, bd.read_btb_target(bpu_idx(ADDR_TK)), bh0, bd.read_local_bht(bpu_idx(ADDR_TK)),
      ghr0, bd.read_ghr(), lidx, lp0, bd.read_local_pht(lidx), gidx, gp0, bd.read_global_pht(gidx)));
    bus_free();
  endtask
endclass : halt_block_and_resume_test


//==============================================================================
// 2.2 halt_carry_freeze
//
// Sheet -- Flow: dua mot nhanh vao tang fetch; assert halt trong N chu ky khi
//   nhanh dang o giua duong ong; nha halt; theo nhanh do toi tang execute. Kiem
//   rieng bon thanh ghi tang mot va bon thanh ghi tang hai.
// Sheet -- Pass: predicted_taken, pred_was_hit, local_carry, global_carry giu
//   nguyen suot thoi gian halt; sau khi nha halt, nhanh toi execute van duoc so
//   voi dung quyet dinh luc fetch; bpu_flush va correction dung.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class halt_carry_freeze_test extends bpu_scene_base;
  `bpu_test_utils(halt_carry_freeze_test, "2.2")

  localparam int N_HALT = 24;

  // Chu ky F: nxpc2 = ADDR_TK (BTB trung + du doan re) => f_valid = 1.
  local task automatic fetch_tk(string tag);
    bpu_fetch_obs_t o;
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_TK), .opcode(OPC_NOP));
    o = snap();
    chk(o.fv === 1'b1, $sformatf("%s: f_valid=%0d tai chu ky F, ky vong 1", tag, o.fv));
  endtask

  // Chu ky ke: halt=1 NGAY, doi nxpc2 sang ADDR_NT (f_valid=0). Neu tang mot
  // khong bi dong bang thi no se nap 0 de len. Tra ve anh chup luc bat dau halt.
  local task automatic start_halt(output bpu_carry_regs_t frozen);
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_NT), .opcode(OPC_NOP), .halt(1'b1));
    frozen = grab_cd();
  endtask

  // Chu ky DAU TIEN co halt tro lai 0: nhanh o tang decode, opcode ADDI.
  local task automatic release_halt();
    apply(.pc(NEU_PC), .nxpc(ADDR_TK), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP), .halt(1'b0));
  endtask

  // Nhanh toi execute tai ADDR_TK.
  local task automatic execute_tk(bit taken, output bpu_fetch_obs_t oX);
    apply(.pc(ADDR_TK), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .halt(1'b0), .is_branch(1'b1), .taken(taken), .offset(32'h40));
    oX = snap();
  endtask

  virtual task test_body();
    bpu_fetch_obs_t  oX;
    bpu_carry_regs_t frozen, cd;
    bit [31:0]       exp_corr;

    //---- A: nap trang thai ---------------------------------------------------
    phase_of("A_train");
    setup_addresses();
    apply_idle(4);
    check_carry_zero("A truoc phep do");

    //---- B: dua nhanh vao FETCH roi dong bang tang MOT ----------------------
    phase_of("B_freeze_stage1");
    fetch_tk("B");
    start_halt(frozen);
    note($sformatf("B: moc luc bat dau halt -- %s", cd_str(frozen)));
    chk(frozen[0] === 1'b1, $sformatf("B: predic_taken_delay_1=%0b luc bat dau halt, ky vong 1", frozen[0]));
    chk(frozen[1] === 1'b1, $sformatf("B: btb_hit_delay_1=%0b luc bat dau halt, ky vong 1", frozen[1]));
    // N chu ky halt, ngo vao tang fetch doi lien tuc: gia tri chot phai tro
    for (int k = 0; k < N_HALT; k++) begin
      apply(.pc((k[0] == 0) ? ADDR_NT : ADDR_UT), .nxpc(ADDR_UT),
            .nxpc2((k[0] == 0) ? ADDR_NT : ADDR_UT), .opcode(OPC_BR), .btf(32'h40),
            .halt(1'b1), .is_branch(1'b1), .taken(k[1]), .offset(32'h40));
      cmp_cd($sformatf("B chu ky halt %0d", k), frozen);
    end
    note($sformatf("B: %0d chu ky halt=1 voi nxpc2/pc/opcode/is_branch doi lien tuc -- ca tam thanh ghi giu nguyen: %s",
                   N_HALT, cd_str(grab_cd())));

    //---- C: nha halt -- quyet dinh chay tiep tu dung cho no dung lai --------
    // Trong SUOT chu ky nay quyet dinh van o tang MOT; canh len KET THUC chu ky
    // moi day no xuong tang hai. Tang hai duoc kiem o pha D.
    phase_of("C_release_and_advance");
    release_halt();
    cd = grab_cd();
    chk(cd[0] === frozen[0], $sformatf("C: predic_taken_delay_1=%0b o chu ky nha halt, ky vong %0b (quyet dinh chua roi tang mot)", cd[0], frozen[0]));
    chk(cd[1] === frozen[1], $sformatf("C: btb_hit_delay_1=%0b, ky vong %0b", cd[1], frozen[1]));
    chk(cd[2] === frozen[2], $sformatf("C: local_delay_1=%0b, ky vong %0b", cd[2], frozen[2]));
    chk(cd[3] === frozen[3], $sformatf("C: global_delay_1=%0b, ky vong %0b", cd[3], frozen[3]));
    chk(cd[4] === 1'b0, $sformatf("C: predic_taken_delay_2=%0b, ky vong 0 -- tang hai chi duoc nap tai CANH LEN ket thuc chu ky nay", cd[4]));

    //---- D: nhanh toi execute, thuc su re -> du doan dung, khong bong bong ---
    phase_of("D_execute_uses_fetch_decision");
    execute_tk(1'b1, oX);
    cd = grab_cd();
    chk(cd[4] === 1'b1, $sformatf("D1: predic_taken_delay_2=%0b, ky vong 1 (quyet dinh luc fetch da qua tang hai)", cd[4]));
    chk(cd[5] === 1'b1, $sformatf("D1: btb_hit_delay_2=%0b, ky vong 1", cd[5]));
    chk(cd[6] === frozen[2], $sformatf("D1: local_delay_2=%0b, ky vong %0b (dung bit da chot luc fetch)", cd[6], frozen[2]));
    chk(cd[7] === frozen[3], $sformatf("D1: global_delay_2=%0b, ky vong %0b (dung bit da chot luc fetch)", cd[7], frozen[3]));
    chk(bd.read_predicted_taken() === 1'b1, $sformatf("D1: predicted_taken=%0d tai execute, ky vong 1", bd.read_predicted_taken()));
    chk(bd.read_pred_was_hit()    === 1'b1, $sformatf("D1: pred_was_hit=%0d tai execute, ky vong 1", bd.read_pred_was_hit()));
    chk(oX.fl === 2'd0, $sformatf("D1: bpu_flush=%0d, ky vong 0 (du doan dung, khong bong bong)", oX.fl));
    chk(oX.cv === 1'b0, $sformatf("D1: corr_valid=%0d, ky vong 0", oX.cv));
    note($sformatf({
      "\n=== 2.2 sau khi nha halt, execute so voi quyet dinh luc FETCH ===\n",
      "  pred_was_hit=%0d predicted_taken=%0d branch_taken=1 -> bpu_flush=%0d corr_valid=%0d\n",
      "  (quyet dinh nay da nam yen suot %0d chu ky halt truoc do)\n",
      "================================================================"},
      bd.read_pred_was_hit(), bd.read_predicted_taken(), oX.fl, oX.cv, N_HALT));

    //---- E: lam lai, lan nay nhanh KHONG re -> phai bao doan sai ------------
    phase_of("E_mispredict_after_halt");
    apply_idle(4);
    check_carry_zero("E truoc phep do");
    fetch_tk("E");
    start_halt(frozen);
    for (int k = 0; k < N_HALT; k++) begin
      apply(.pc(ADDR_UT), .nxpc(ADDR_UT), .nxpc2(ADDR_NT), .opcode(OPC_BR), .btf(32'h40), .halt(1'b1));
      cmp_cd($sformatf("E chu ky halt %0d", k), frozen);
    end
    release_halt();
    execute_tk(1'b0, oX);
    exp_corr = ADDR_TK + 32'd4;
    chk(bd.read_predicted_taken() === 1'b1, $sformatf("E: predicted_taken=%0d tai execute, ky vong 1", bd.read_predicted_taken()));
    chk(oX.fl === 2'd2,  $sformatf("E: bpu_flush=%0d, ky vong 2 (doan re nhung nhanh khong re)", oX.fl));
    chk(oX.cv === 1'b1,  $sformatf("E: corr_valid=%0d, ky vong 1", oX.cv));
    chk(oX.outp === exp_corr, $sformatf("E: bpu_nxpc2=0x%08h, ky vong 0x%08h (pc + 4, duong hieu chinh cho nhanh khong re)", oX.outp, exp_corr));
    chk(oX.outv === 1'b1, $sformatf("E: bpu_nxpc2_valid=%0d, ky vong 1", oX.outv));
    bus_free();
  endtask
endclass : halt_carry_freeze_test
