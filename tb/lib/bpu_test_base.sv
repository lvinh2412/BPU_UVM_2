//------------------------------------------------------------------------------
// FILE: lib/bpu_test_base.sv
//
// CLASS: bpu_test_base -- lop cha cua MOI test, giu toan bo NGUYEN THUY dung
// chung. Test chi con viet test_body() va goi cac ham/task o day.
//
// Muc luc (tim theo chu "SECTION"):
//   1. Khung test        : test_id/test_label, chk(), phase_of(), note(), bao cao
//   2. Kich thich nhanh  : drive_branch(), idle_cycles(), train_*(), warm_cycle()
//   3. Doc tin hieu RTL  : rd_reg()
//   4. Duong ong 3 tang  : h (bpu_pipe_helper), pipe_probe(), assert_cell(), show_obs()
//   5. Lai tung chu ky   : apply(), apply_idle(), bus_free(), snap(), observe_at()
//   6. Reset             : reset_by_force(), reset_by_sequence()
//   7. Kiem trang thai   : check_carry_zero(), grab_cd(), snapshot/compare_state(),
//                          check_defaults(), dirty_state()
//   8. Cua so backdoor   : bd_window_open(), bd_set_*(), bd_restore_all()
//   9. Kiem bo dem       : drive_chk_local_pht(), drive_chk_global_pht()
//  10. Quet nhieu entry  : sweep_bad(), sweep_report()
//  11. Bo sinh ngau nhien: make_gen(), chk_no_x(), chk_no_miscompare()
//
// HAI CHE DO LAI KICH THICH
//   (a) drive_branch()/idle_cycles() : qua sequence + driver, moi nhanh = 2 chu
//       ky (co chu ky ha is_branch). Don gian, scoreboard luon song.
//   (b) apply()/h.push_branch()      : lai DUNG MOT chu ky, dung khi can kiem
//       soat tung tang cua duong ong. apply() EP net cua interface (monitor va
//       DUT thay cung gia tri => reference model van chay dung => scoreboard
//       song), nhung force la sticky: PHAI goi bus_free() truoc khi quay lai (a).
//------------------------------------------------------------------------------

class bpu_test_base extends bpu_base_test;

  //--------------------------------------------------------------------------
  // Hang so dung chung
  //--------------------------------------------------------------------------
  // Ba dia chi chuan, huan luyen bang duong cap nhat THAT (setup_addresses()):
  localparam bit [31:0] ADDR_TK = 32'h0000_0100;   // idx 64  : BTB hop le + du doan RE
  localparam bit [31:0] ADDR_NT = 32'h0000_0200;   // idx 128 : BTB hop le + du doan KHONG RE
  localparam bit [31:0] ADDR_UT = 32'h0000_0300;   // idx 192 : chua bao gio duoc ghi
  // Dia chi trung tinh cho cac chan khong phai doi tuong do. Ba chi muc
  // 1020/1021/1022 trung voi khe trong cua bpu_pipe_helper.
  localparam bit [31:0] NEU_PC    = 32'h0000_0FF0;
  localparam bit [31:0] NEU_NXPC  = 32'h0000_0FF4;
  localparam bit [31:0] NEU_NXPC2 = 32'h0000_0FF8;
  localparam bit [6:0]  OPC_BR    = 7'b1100011;    // BCC -- lenh re nhanh
  localparam bit [6:0]  OPC_NOP   = 7'b0010011;    // ADDI -- khong phai lenh re

  //--------------------------------------------------------------------------
  // Trang thai
  //--------------------------------------------------------------------------
  string test_id    = "0.0";        // ma muc testplan, dat boi `bpu_test_utils
  string test_label = "BPU_TEST";   // tien to moi dong log
  string cur_phase  = "-";
  int    err        = 0;
  int    err_in_phase[string];

  bpu_backdoor     bd;              // truy cap trang thai noi bo DUT
  bpu_pipe_helper  h;               // day nhanh qua ba tang, tu chup quan sat
  bpu_coherent_gen gen;             // bo sinh ngau nhien (null cho toi make_gen())
  virtual bpu_if   pvif;            // de bat canh clock trong apply()

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  //==========================================================================
  // SECTION 1: KHUNG TEST
  //==========================================================================

  function void build_phase(uvm_phase phase);
    test_label = $sformatf("TEST_%s (%s)", test_id, get_type_name());
    uvm_config_wrapper::set(this,
        "tb.clock_and_reset.agent.sequencer.run_phase",
        "default_sequence", clk10_rst5_seq::get_type());
    super.build_phase(phase);
    h = bpu_pipe_helper::type_id::create("h");
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    bd   = tb.module_env.backdoor;
    // connect_phase chay tu duoi len, nen agent da gan monitor.vif xong.
    pvif = tb.bpu.tx_agent.monitor.vif;
    h.connect(tb.bpu.tx_agent.sequencer, bd);
  endfunction

  // Khung chung: giu objection, cho reset dau tien xong, roi goi test_body().
  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this, test_id);
    #100ns;
    test_body();
    phase.drop_objection(this, test_id);
  endtask

  // Noi dung cua tung test.
  virtual task test_body();
  endtask

  // Dat nhan pha. Moi loi phat ra sau day se mang nhan nay.
  protected function void phase_of(string p);
    cur_phase = p;
    if (!err_in_phase.exists(p)) err_in_phase[p] = 0;
    `uvm_info(test_label, $sformatf(">>> PHA [%s]", p), UVM_LOW)
  endfunction

  // Phep kiem: sai thi dem loi va phat uvm_error kem nhan pha.
  protected function void chk(bit cond, string msg);
    if (!cond) begin
      err++;
      err_in_phase[cur_phase]++;
      `uvm_error(test_label, $sformatf("[%s] %s", cur_phase, msg))
    end
  endfunction

  // Ghi chu quan trong ra log (luon in, bat ke verbosity).
  protected function void note(string msg);
    `uvm_info(test_label, msg, UVM_NONE)
  endfunction

  // Goi o dau test_body() khi muc nay ep trang thai noi bo bang backdoor: khi
  // do reference model khong theo kip nen scoreboard khong con la checker hop
  // le; phep kiem that nam o cac chk() doc backdoor.
  protected function void scoreboard_not_applicable(string why);
    tb.module_env.scoreboard.set_report_severity_override(UVM_ERROR, UVM_INFO);
    note({"scoreboard KHONG ap dung cho muc nay (ep trang thai noi bo bang backdoor): ", why});
  endfunction

  // Tong ket: cac muc dung bo sinh duoc kiem them nhat quan duong ong va X.
  function void report_phase(uvm_phase phase);
    string s = "";
    super.report_phase(phase);
    if (gen != null) gen_final_checks();
    foreach (err_in_phase[p])
      s = {s, $sformatf("    pha %-32s : %0d loi\n", p, err_in_phase[p])};
    if (err == 0)
      `uvm_info(test_label, $sformatf("PASSED\n%s", s), UVM_NONE)
    else
      `uvm_error(test_label, $sformatf("FAILED: %0d loi\n%s", err, s))
  endfunction

  //==========================================================================
  // SECTION 2: KICH THICH MUC NHANH (qua sequence + driver)
  //==========================================================================

  // Mot nhanh tai pc: fetch thay opcode BCC va execute giai quyet no trong cung
  // chu ky; chu ky ke tiep ha is_branch. #1ns de canh @(negedge) ke tiep khong
  // bi lo.
  protected task automatic drive_branch(bit [31:0] pc, bit tk, bit [31:0] offset = 32'h40);
    bpu_branch_vseq v;
    v = bpu_branch_vseq::type_id::create($sformatf("b_%0t", $time));
    v.pc = pc; v.taken = tk; v.offset = offset; v.btf = offset;
    v.start(tb.bpu.tx_agent.sequencer);
    #1ns;
  endtask

  // n chu ky nghi (khong nhanh o ca fetch lan execute).
  protected task automatic idle_cycles(int n);
    bpu_idle_vseq vi;
    vi = bpu_idle_vseq::type_id::create($sformatf("i_%0t", $time));
    vi.count = n;
    vi.start(tb.bpu.tx_agent.sequencer);
    #1ns;
  endtask

  // Huan luyen pc thanh "BTB hit + du doan RE tai nxpc2".
  //   BHT rong 12 bit nen lich su bao hoa 0xFFF sau 12 nhanh, va
  //   local_pht[0xFFF] chi BAT DAU duoc ghi tu nhanh thu 13 -> can ~24 vong.
  protected task automatic train_predict_taken(bit [31:0] pc, int n = 24);
    repeat (n) drive_branch(pc, 1'b1, 32'h40);
  endtask

  // Huan luyen pc thanh "BTB hit + du doan KHONG RE tai nxpc2".
  //   Nhanh not-taken khong lam dich lich su khoi 0, nen moi lan deu dung
  //   local_pht[0]: WT (init khi miss) -> WNT -> SNT.
  protected task automatic train_predict_not_taken(bit [31:0] pc, int n = 6);
    repeat (n) drive_branch(pc, 1'b0, 32'h40);
  endtask

  // Vong "1 re + 10 khong re" tai mot dia chi LA:
  //   - nhanh dau co btb_valid_pc = 0 nen bpu_predictor.v ghi THANG WT vao
  //     local_pht[0] (keo bit local cua moi dia chi co local_bht = 0 len 1);
  //   - 10 nhanh khong re sau do day GHR ve 0 va chi ghi local_pht[1,2,4,...],
  //     khong cham local_pht[0] nua.
  protected task automatic warm_cycle(bit [31:0] a);
    drive_branch(a, 1'b1, 32'h40);
    repeat (10) drive_branch(a, 1'b0, 32'h40);
  endtask

  //==========================================================================
  // SECTION 3: DOC TIN HIEU RTL KHONG CO TRONG BACKDOOR
  //==========================================================================

  // Doc mot tin hieu trong bpu_hw_top.dut.u_bpu_reg (toi 32 bit).
  protected function bit [31:0] rd_reg(string sig);
    uvm_hdl_data_t v;
    if (!uvm_hdl_read({"bpu_hw_top.dut.u_bpu_reg.", sig}, v))
      `uvm_error(test_label, $sformatf("khong doc duoc u_bpu_reg.%s", sig))
    return v[31:0];
  endfunction

  //==========================================================================
  // SECTION 4: DUONG ONG BA TANG (bpu_pipe_helper)
  //
  //   Quy tac doc: helper chup quan sat tai dung canh len, test KHONG tu doc
  //   tin hieu phu thuoc carry-down.
  //   pred_was_hit(F+2)    = btb_valid_nxpc2(F)          <- chon nxpc2
  //   predicted_taken(F+2) = f_valid(F) | d_valid(F+1)   <- chon nxpc2 + opcode
  //   d_valid(F+1) = fetch_is_branch(opcode) && !btb_valid_nxpc && ready
  //   => opcode tai DECODE = ADDI thi d_valid = 0 BAT KE btb_valid_nxpc.
  //==========================================================================

  // Day MOT nhanh don le qua ba tang (sau 4 chu ky don sach), tra ve quan sat
  // tai F, F+1, F+2, F+3:
  //   o[0] = F   : ngo ra tang FETCH   (f_valid neu co)
  //   o[1] = F+1 : ngo ra tang DECODE  (d_valid neu co)
  //   o[2] = F+2 : ngo ra tang EXECUTE (flush / correction)
  //   o[3] = F+3 : quyet dinh da roi di
  // fl_f / fl_d / fl_x : flush_in dat rieng cho tung chu ky.
  protected task automatic pipe_probe(input  bit [31:0] pc,
                                      input  bit [31:0] nxpc2,
                                      input  bit        taken,
                                      input  bit [6:0]  opc       = OPC_NOP,
                                      input  bit [31:0] offset    = 32'h40,
                                      input  bit [31:0] btf       = 32'h40,
                                      input  bit [1:0]  fl_f      = 2'd0,
                                      input  bit [1:0]  fl_d      = 2'd0,
                                      input  bit [1:0]  fl_x      = 2'd0,
                                      input  bit        is_branch = 1'b1,
                                      output bpu_pipe_obs_t o[4]);
    int base;
    h.idle(4);
    base = h.num_cycles();
    h.push_branch(.pc(pc), .taken(taken), .offset(offset), .opcode(opc),
                  .flush_in(fl_f), .halt(1'b0), .btf(btf), .is_branch(is_branch),
                  .ovr_nxpc2(1'b1), .nxpc2(nxpc2));
    h.idle(1, fl_d, 1'b0);   // F+1
    h.idle(1, fl_x, 1'b0);   // F+2
    h.idle(1);               // F+3
    for (int k = 0; k < 4; k++) o[k] = h.obs_at_cycle(base + k);
  endtask

  // Kiem rang mot o cua ma tran DA DUNG DUOC dung nhu y (pred_was_hit,
  // predicted_taken tai F+2) truoc khi doi chieu ngo ra. Thieu buoc nay, mot
  // o dung sai canh se "pass" nham.
  protected function void assert_cell(string lbl, bpu_pipe_obs_t o,
                                      bit exp_hit, bit exp_predT);
    chk(o.pred_was_hit    === exp_hit,
        $sformatf("%s: pred_was_hit=%0d, canh dung SAI (can %0d)", lbl, o.pred_was_hit, exp_hit));
    chk(o.predicted_taken === exp_predT,
        $sformatf("%s: predicted_taken=%0d, canh dung SAI (can %0d)", lbl, o.predicted_taken, exp_predT));
  endfunction

  protected function void show_obs(string tag, bpu_pipe_obs_t o);
    note($sformatf(
      "%-22s cyc=%0d pc=0x%08h | predT=%0d hit=%0d locC=%0d glbC=%0d | flush=%0d nxpc2=0x%08h vld=%0d",
      tag, o.cycle, o.pc, o.predicted_taken, o.pred_was_hit, o.local_carry, o.global_carry,
      o.bpu_flush, o.bpu_nxpc2, o.bpu_nxpc2_valid));
  endfunction

  //==========================================================================
  // SECTION 5: LAI TUNG CHU KY BANG CACH EP CHAN GIAO TIEP
  //==========================================================================

  // Lai DUNG MOT chu ky: dat gia tri tai canh XUONG roi tra ve o giua chu ky.
  // Luc tra ve, moi thanh ghi VAN giu gia tri cua chu ky nay, con ngo ra to hop
  // DA phan anh bo ngo vao vua dat -- dung diem nhin cua bpu_pipe_helper.
  protected task automatic apply(input bit [31:0] pc,
                                 input bit [31:0] nxpc,
                                 input bit [31:0] nxpc2,
                                 input bit [6:0]  opcode,
                                 input bit [31:0] btf       = 32'h0,
                                 input bit [1:0]  flush_in  = 2'd0,
                                 input bit        halt      = 1'b0,
                                 input bit        is_branch = 1'b0,
                                 input bit        taken     = 1'b0,
                                 input bit [31:0] offset    = 32'h0);
    @(negedge pvif.clock);
    apply_now(pc, nxpc, nxpc2, opcode, btf, flush_in, halt, is_branch, taken, offset);
  endtask

  // Dat bo ngo vao NGAY, khong cho canh xuong. Chi dung khi phai doi ngo vao
  // trong CUNG nua chu ky voi mot su kien bat dong bo (vd vua assert rst_n).
  protected task automatic apply_now(input bit [31:0] pc,
                                     input bit [31:0] nxpc,
                                     input bit [31:0] nxpc2,
                                     input bit [6:0]  opcode,
                                     input bit [31:0] btf       = 32'h0,
                                     input bit [1:0]  flush_in  = 2'd0,
                                     input bit        halt      = 1'b0,
                                     input bit        is_branch = 1'b0,
                                     input bit        taken     = 1'b0,
                                     input bit [31:0] offset    = 32'h0);
    bd.force_predict_inputs(
        .pc(pc), .nxpc(nxpc), .fetch_opcode(opcode), .branch_target_fetch(btf),
        .flush_in(flush_in), .halt(halt), .nxpc2(nxpc2), .is_branch(is_branch),
        .branch_taken(taken), .branch_offset(offset));
    #1ns;
  endtask

  // n chu ky nghi trung tinh (khong nhanh, tang fetch tat vi nxpc2 trung tinh).
  protected task automatic apply_idle(int n = 1, bit [1:0] flush_in = 2'd0, bit halt = 1'b0);
    repeat (n) apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2),
                     .opcode(OPC_NOP), .flush_in(flush_in), .halt(halt));
  endtask

  protected task automatic apply_now_idle();
    apply_now(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP));
  endtask

  // Tra bus lai cho driver. LUON goi truoc khi dung lai drive_branch()/helper.
  protected task automatic bus_free();
    bd.release_predict_inputs();
    repeat (3) @(negedge pvif.clock);
    #1ns;
  endtask

  // Chup toan bo diem quan sat cua chu ky hien tai (goi ngay sau apply()).
  protected function bpu_fetch_obs_t snap();
    bpu_fetch_obs_t o;
    o.hit  = bd.read_btb_valid_nxpc2();
    o.lp   = bd.read_local_pht_data_nxpc2();
    o.gp   = bd.read_global_pht_data_nxpc2();
    o.ch   = bd.read_choice_data_nxpc2();
    o.pt   = bd.read_predict_taken_nxpc2();
    o.tgt  = bd.read_btb_target_nxpc2();
    o.fib  = bd.read_fetch_is_branch();
    o.fr   = bd.read_fetch_ready();
    o.fv   = bd.read_f_valid();
    o.dv   = bd.read_d_valid();
    o.cv   = bd.read_corr_valid();
    o.outp = bd.read_bpu_nxpc2();
    o.outv = bd.read_bpu_nxpc2_valid();
    o.fl   = bd.read_bpu_flush();
    return o;
  endfunction

  // Giu nxpc2 tai mot dia chi trong hai chu ky roi chup. Chay o DUONG THAT nen
  // day cung la nguon lay mau cho cac coverpoint co iff(btb_valid_nxpc2).
  protected task automatic observe_at(input bit [31:0] nxpc2, input bit [1:0] flush_in,
                                      output bpu_fetch_obs_t o);
    repeat (2) apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(nxpc2), .opcode(OPC_NOP),
                     .flush_in(flush_in));
    o = snap();
  endtask

  protected function void show_fetch(string tag, bit [31:0] nxpc2, bpu_fetch_obs_t o);
    note($sformatf(
      "%-30s nxpc2=0x%08h | hit=%0d local=%0d(%02b) global=%0d(%02b) choice=%0d(%02b) => predT=%0d | tgt=0x%08h out=0x%08h vld=%0d",
      tag, nxpc2, o.hit, o.lp[1], o.lp, o.gp[1], o.gp, o.ch[1], o.ch, o.pt,
      o.tgt, o.outp, o.outv));
  endfunction

  // Kiem tien de cua mot canh dung o tang fetch (ba bit dau vao bo chon).
  protected function void assert_fetch_cell(string lbl, bpu_fetch_obs_t o,
                                            bit exp_hit, bit exp_l, bit exp_g, bit exp_c);
    chk(o.hit   === exp_hit, $sformatf("%s: btb_valid_nxpc2=%0d, canh dung SAI (can %0d)", lbl, o.hit, exp_hit));
    chk(o.lp[1] === exp_l,   $sformatf("%s: local_pht_data_nxpc2[1]=%0d, canh dung SAI (can %0d)", lbl, o.lp[1], exp_l));
    chk(o.gp[1] === exp_g,   $sformatf("%s: global_pht_data_nxpc2[1]=%0d, canh dung SAI (can %0d)", lbl, o.gp[1], exp_g));
    chk(o.ch[1] === exp_c,   $sformatf("%s: choice_data_nxpc2[1]=%0d, canh dung SAI (can %0d)", lbl, o.ch[1], exp_c));
  endfunction

  //==========================================================================
  // SECTION 6: RESET GIUA CHUNG
  //==========================================================================

  // Assert rst_n bang cach ep net cua clock_and_reset_if. Can thiet vi UVC chi
  // lai reset tai canh len clk, nen sequence khong assert giua chu ky duoc.
  // Cung la cach DUY NHAT de dung lai canh nhieu lan trong mot lan chay: cac
  // chuoi huan luyen chi cho dung ket qua khi xuat phat tu trang thai sach.
  protected task automatic reset_by_force(int n_cycles = 3);
    bd.force_tb_reset(1'b1);
    repeat (n_cycles) @(negedge pvif.clock);
    bd.release_tb_reset();
    repeat (3) @(negedge pvif.clock);
    h.reset_pipe();
    #50ns;
  endtask

  // Chu trinh reset "that", di qua clock_and_reset UVC.
  protected task automatic reset_by_sequence();
    clk10_rst5_seq cr;
    cr = clk10_rst5_seq::type_id::create($sformatf("cr_%0t", $time));
    cr.start(tb.clock_and_reset.agent.sequencer);
    h.reset_pipe();
    #100ns;
  endtask

  //==========================================================================
  // SECTION 7: KIEM TRANG THAI NOI BO
  //==========================================================================

  // Tam thanh ghi carry-down, doc trong MOT anh chup.
  protected function bpu_carry_regs_t grab_cd();
    bpu_carry_regs_t cd;
    cd[0] = bd.read_predic_taken_delay_1();
    cd[1] = bd.read_btb_hit_delay_1();
    cd[2] = bd.read_local_delay_1();
    cd[3] = bd.read_global_delay_1();
    cd[4] = bd.read_predic_taken_delay_2();
    cd[5] = bd.read_btb_hit_delay_2();
    cd[6] = bd.read_local_delay_2();
    cd[7] = bd.read_global_delay_2();
    return cd;
  endfunction

  protected function string cd_str(bpu_carry_regs_t cd);
    return $sformatf("tang1[steer=%0b hit=%0b local=%0b global=%0b] tang2[predT=%0b hit=%0b local=%0b global=%0b]",
                     cd[0], cd[1], cd[2], cd[3], cd[4], cd[5], cd[6], cd[7]);
  endfunction

  protected function string cd_name(int i);
    case (i)
      0: return "predic_taken_delay_1";  1: return "btb_hit_delay_1";
      2: return "local_delay_1";         3: return "global_delay_1";
      4: return "predic_taken_delay_2";  5: return "btb_hit_delay_2";
      6: return "local_delay_2";         default: return "global_delay_2";
    endcase
  endfunction

  // Doc tam thanh ghi NGAY BAY GIO va so voi mot anh chup truoc do.
  protected function void cmp_cd(string tag, bpu_carry_regs_t ref_cd);
    bpu_carry_regs_t cd = grab_cd();
    foreach (cd[i])
      chk(cd[i] === ref_cd[i],
          $sformatf("%s: %s = %0b, ky vong %0b -- halt phai dong bang thanh ghi nay",
                    tag, cd_name(i), cd[i], ref_cd[i]));
  endfunction

  protected function void check_carry_zero(string tag);
    bpu_carry_regs_t cd = grab_cd();
    foreach (cd[i])
      chk(cd[i] === 1'b0, $sformatf("%s: %s != 0", tag, cd_name(i)));
  endfunction

  // Anh chup toan bo sau bang + GHR, de so truoc/sau mot doan khong duoc ghi.
  protected bit        st_btb_v  [1024];
  protected bit [31:0] st_btb_t  [1024];
  protected bit [11:0] st_bht    [1024];
  protected bit [1:0]  st_lpht   [4096];
  protected bit [1:0]  st_gpht   [1024];
  protected bit [1:0]  st_choice [1024];
  protected bit [9:0]  st_ghr;

  protected function void snapshot_state();
    for (int i = 0; i < 1024; i++) begin
      st_btb_v[i]  = bd.read_btb_valid(i);
      st_btb_t[i]  = bd.read_btb_target(i);
      st_bht[i]    = bd.read_local_bht(i);
      st_gpht[i]   = bd.read_global_pht(i);
      st_choice[i] = bd.read_choice(i);
    end
    for (int i = 0; i < 4096; i++) st_lpht[i] = bd.read_local_pht(i);
    st_ghr = bd.read_ghr();
  endfunction

  // So trang thai hien tai voi anh chup: MOT loi cho moi bang, tra ve tong so o lech.
  protected function int compare_state(string tag);
    int d_bv = 0, d_bt = 0, d_bh = 0, d_lp = 0, d_gp = 0, d_ch = 0, d_gh = 0;
    for (int i = 0; i < 1024; i++) begin
      if (bd.read_btb_valid(i)  !== st_btb_v[i])  d_bv++;
      if (bd.read_btb_target(i) !== st_btb_t[i])  d_bt++;
      if (bd.read_local_bht(i)  !== st_bht[i])    d_bh++;
      if (bd.read_global_pht(i) !== st_gpht[i])   d_gp++;
      if (bd.read_choice(i)     !== st_choice[i]) d_ch++;
    end
    for (int i = 0; i < 4096; i++) if (bd.read_local_pht(i) !== st_lpht[i]) d_lp++;
    if (bd.read_ghr() !== st_ghr) d_gh = 1;
    chk(d_bv == 0, $sformatf("%s: btb_valid  lech %0d o", tag, d_bv));
    chk(d_bt == 0, $sformatf("%s: btb_target lech %0d o", tag, d_bt));
    chk(d_bh == 0, $sformatf("%s: local_bht  lech %0d o", tag, d_bh));
    chk(d_lp == 0, $sformatf("%s: local_pht  lech %0d o", tag, d_lp));
    chk(d_gp == 0, $sformatf("%s: global_pht lech %0d o", tag, d_gp));
    chk(d_ch == 0, $sformatf("%s: choice     lech %0d o", tag, d_ch));
    chk(d_gh == 0, $sformatf("%s: ghr        lech (0x%03h -> 0x%03h)", tag, st_ghr, bd.read_ghr()));
    return d_bv + d_bt + d_bh + d_lp + d_gp + d_ch + d_gh;
  endfunction

  // SAU bang + GHR + TAM thanh ghi carry-down deu o gia tri mac dinh sau reset.
  protected function void check_defaults(string tag);
    int m;
    m = bd.check_table_zero(0);
    chk(m == 0, $sformatf("%s: btb_valid  -- %0d/1024 o khac 0", tag, m));
    m = bd.count_btb_target_nonzero();
    chk(m == 0, $sformatf("%s: btb_target -- %0d/1024 o khac 0", tag, m));
    m = bd.check_table_zero(1);
    chk(m == 0, $sformatf("%s: local_bht  -- %0d/1024 o khac 0 (12 bit)", tag, m));
    m = bd.check_table_zero(2);
    chk(m == 0, $sformatf("%s: local_pht  -- %0d/4096 o khac SNT", tag, m));
    m = bd.check_table_zero(3);
    chk(m == 0, $sformatf("%s: global_pht -- %0d/1024 o khac SNT", tag, m));
    m = bd.count_choice_not_wnt();
    chk(m == 0, $sformatf("%s: choice     -- %0d/1024 o khac WNT(2'b01)", tag, m));
    chk(bd.read_ghr() === 10'd0, $sformatf("%s: ghr = 0x%03h, ky vong 0", tag, bd.read_ghr()));
    check_carry_zero(tag);
  endfunction

  // So o KHAC mac dinh -- chung minh phep kiem sau reset khong vacuous.
  protected function int count_dirty();
    return bd.check_table_zero(0) + bd.check_table_zero(1)
         + bd.check_table_zero(2) + bd.check_table_zero(3)
         + bd.count_btb_target_nonzero() + bd.count_choice_not_wnt()
         + ((bd.read_ghr() !== 10'd0) ? 1 : 0);
  endfunction

  // Lam ban toan bo trang thai bang DUONG CAP NHAT THAT roi xac nhan da ban.
  protected task automatic dirty_state(string tag);
    int dirty;
    train_predict_taken(ADDR_TK, 24);
    train_predict_not_taken(ADDR_NT, 8);
    drive_branch(32'h0000_0500, 1'b1, 32'h80);
    drive_branch(32'h0000_0600, 1'b0, 32'h40);
    drive_branch(32'h0000_0700, 1'b1, 32'hFFFF_FFC0);
    dirty = count_dirty();
    chk(dirty > 0, {tag, ": trang thai chua bi lam ban -- phep kiem sau reset se vacuous"});
    note($sformatf("%s: truoc reset co %0d o khac mac dinh", tag, dirty));
  endtask

  //==========================================================================
  // SECTION 8: CUA SO BACKDOOR -- dat bang noi bo roi TRA LAI dung gia tri cu
  //
  //   Ghi thang vao bang khong tu khoi phuc: o bi ghi de giu gia tri gan nhu
  //   vinh vien -> bang cua DUT lech khoi shadow state cua reference. Vi vay
  //   moi lan dat deu qua bd_set_* de nho gia tri goc, va bd_restore_all() ghi
  //   nguoc ve khi ket thuc.
  //   De scoreboard van song, suot cua so dung flush_in = 2 va is_branch = 0:
  //   f_valid = d_valid = corr_valid = 0 o ca DUT lan reference -> khong lech.
  //==========================================================================
  protected int       sv_l_i[$];   protected bit [1:0] sv_l_v[$];
  protected int       sv_g_i[$];   protected bit [1:0] sv_g_v[$];
  protected int       sv_c_i[$];   protected bit [1:0] sv_c_v[$];
  protected bit       sv_ghr_used; protected bit [9:0] sv_ghr_v;

  // Dua bus ve trang thai IM LANG (nxpc2 trung tinh + flush_in = 2) TRUOC khi
  // cham vao bang, de khong co chu ky nao f_valid cua DUT khac reference.
  protected task automatic bd_window_open();
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP), .flush_in(2'd2));
  endtask

  protected task automatic bd_set_local_pht(int idx, bit [1:0] v);
    if (!(idx inside {sv_l_i})) begin
      sv_l_i.push_back(idx); sv_l_v.push_back(bd.read_local_pht(idx));
    end
    bd.deposit_local_pht(idx, v);
  endtask

  protected task automatic bd_set_global_pht(int idx, bit [1:0] v);
    if (!(idx inside {sv_g_i})) begin
      sv_g_i.push_back(idx); sv_g_v.push_back(bd.read_global_pht(idx));
    end
    bd.deposit_global_pht(idx, v);
  endtask

  protected task automatic bd_set_choice(int idx, bit [1:0] v);
    if (!(idx inside {sv_c_i})) begin
      sv_c_i.push_back(idx); sv_c_v.push_back(bd.read_choice(idx));
    end
    bd.deposit_choice(idx, v);
  endtask

  protected task automatic bd_set_ghr(bit [9:0] v);
    if (!sv_ghr_used) begin sv_ghr_used = 1'b1; sv_ghr_v = bd.read_ghr(); end
    bd.deposit_ghr(v);
  endtask

  protected task automatic bd_restore_all();
    foreach (sv_l_i[i]) bd.deposit_local_pht(sv_l_i[i], sv_l_v[i]);
    foreach (sv_g_i[i]) bd.deposit_global_pht(sv_g_i[i], sv_g_v[i]);
    foreach (sv_c_i[i]) bd.deposit_choice(sv_c_i[i], sv_c_v[i]);
    if (sv_ghr_used) begin bd.deposit_ghr(sv_ghr_v); sv_ghr_used = 1'b0; end
    sv_l_i.delete(); sv_l_v.delete();
    sv_g_i.delete(); sv_g_v.delete();
    sv_c_i.delete(); sv_c_v.delete();
    // Bon thanh ghi carry-down local/global da lech trong cua so; chay them vai
    // chu ky is_branch = 0 de chung nap lai tu trang thai THAT.
    apply_idle(4);
  endtask

  // Kiem lai rang cua so backdoor da tra bang ve dung nhu truoc.
  protected function void check_restored(int lidx, int gidx, int cidx,
                                         bit [1:0] l0, bit [1:0] g0, bit [1:0] c0, bit [9:0] ghr0);
    chk(bd.read_local_pht(lidx)  === l0,
        $sformatf("khoi phuc: local_pht[0x%03h]=%02b, ky vong %02b", lidx, bd.read_local_pht(lidx), l0));
    chk(bd.read_global_pht(gidx) === g0,
        $sformatf("khoi phuc: global_pht[%0d]=%02b, ky vong %02b", gidx, bd.read_global_pht(gidx), g0));
    chk(bd.read_choice(cidx)     === c0,
        $sformatf("khoi phuc: choice[%0d]=%02b, ky vong %02b", cidx, bd.read_choice(cidx), c0));
    chk(bd.read_ghr()            === ghr0,
        $sformatf("khoi phuc: ghr=0x%03h, ky vong 0x%03h", bd.read_ghr(), ghr0));
  endfunction

  //==========================================================================
  // SECTION 9: MOT NHANH ROI KIEM BO DEM
  //==========================================================================

  protected task automatic drive_chk_local_pht(bit [31:0] pc, bit tk, int idx,
                                               bit [1:0] exp, string lbl);
    drive_branch(pc, tk);
    chk(bd.read_local_pht(idx) === exp,
        $sformatf("%s: local_pht[%0d]=2'b%02b, ky vong 2'b%02b", lbl, idx, bd.read_local_pht(idx), exp));
  endtask

  protected task automatic drive_chk_global_pht(bit [31:0] pc, bit tk, int idx,
                                                bit [1:0] exp, string lbl);
    drive_branch(pc, tk);
    chk(bd.read_global_pht(idx) === exp,
        $sformatf("%s: global_pht[%0d]=2'b%02b, ky vong 2'b%02b", lbl, idx, bd.read_global_pht(idx), exp));
  endtask

  //==========================================================================
  // SECTION 10: QUET NHIEU ENTRY -- chi in vai loi dau, cuoi cung bao tong
  //==========================================================================
  localparam int SWEEP_PRINT = 5;

  protected function void sweep_bad(ref int n_bad, input string msg);
    n_bad++;
    if (n_bad <= SWEEP_PRINT) chk(1'b0, msg);
  endfunction

  protected function void sweep_report(string what, int n_bad, int total);
    `uvm_info(test_label, $sformatf("%s: sai %0d/%0d", what, n_bad, total), UVM_LOW)
    if (n_bad > SWEEP_PRINT)
      chk(1'b0, $sformatf("%s: tong cong %0d/%0d sai (chi in %0d dau)",
                          what, n_bad, total, SWEEP_PRINT));
  endfunction

  //==========================================================================
  // SECTION 11: BO SINH KICH THICH NHAT QUAN DUONG ONG (bpu_coherent_gen)
  //   Khong muc nao dung gen ep trang thai noi bo -> scoreboard luon song.
  //==========================================================================

  protected function void make_gen(bit [31:0] seed = 32'd2);
    gen = bpu_coherent_gen::type_id::create("gen");
    gen.connect(tb.bpu.tx_agent.sequencer, bd);
    gen.set_seed(seed);
    gen.clear_stats();
  endfunction

  protected function void chk_no_x();
    chk(gen.n_x_seen == 0, $sformatf("%0d chu ky co gia tri X tren ngo ra BPU", gen.n_x_seen));
  endfunction

  // DUT khop reference suot ca lan chay.
  protected function void chk_no_miscompare(int min_compares);
    bpu_scoreboard sb = tb.module_env.scoreboard;
    note($sformatf("scoreboard: compares=%0d match=%0d miscompare=%0d",
                   sb.total_compares, sb.match_count, sb.miscompare_count));
    chk(sb.miscompare_count == 0,
        $sformatf("%0d miscompare -- DUT lech khoi reference duoi kich thich ngau nhien", sb.miscompare_count));
    chk(sb.total_compares >= min_compares,
        $sformatf("chi %0d lan so sanh (< %0d) -- co the treo", sb.total_compares, min_compares));
  endfunction

  // Goi tu dong trong report_phase khi test co dung gen.
  protected function void gen_final_checks();
    phase_of("FINAL_gen");
    note({"tong ket: ", gen.stats()});
    chk(gen.n_coherence_bad == 0, $sformatf(
        {"%0d/%0d bo ba (nxpc2,nxpc,pc) VI PHAM nhat quan duong ong: dia chi o nxpc2 tai T ",
         "khong phai dia chi toi pc tai T+2, nen quyet dinh fetch duoc so voi mot nhanh KHAC"},
        gen.n_coherence_bad, gen.n_coherence_checked));
    chk_no_x();
  endfunction

endclass : bpu_test_base
