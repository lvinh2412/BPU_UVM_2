//------------------------------------------------------------------------------
// FILE: tests/t16_stress_tests.sv -- Nhom 16: Stress / Random
//   16.1 random_pipeline_coherent
//   16.2 stress_long_run
//   16.3 stress_btb_full
//
// 16.1 va 16.2 chay tren bpu_coherent_gen; nhat quan duong ong va X duoc kiem
// tu dong o report_phase (gen_final_checks). Khong muc nao ep trang thai noi bo
// nen scoreboard luon la checker hop le.
//------------------------------------------------------------------------------


//==============================================================================
// 16.1 random_pipeline_coherent
//
// Sheet -- Flow: kich thich ngau nhien quy mo lon NHUNG NHAT QUAN DUONG ONG,
//   kem halt ~30%, flush_in gom ca 3, chen reset, nhanh sat nhau.
// Sheet -- Pass: khong treo, khong X, tat dinh, scoreboard 0 miscompare, moi
//   nhanh tai execute duoc so voi dung quyet dinh fetch cua chinh no.
// Sheet -- TU KIEM: "neu kich thich khong lai nxpc2 thi tang fetch khong bao gio
//   hoat dong va test nay phai phat hien ra".
//==============================================================================
class random_pipeline_coherent_test extends bpu_scene_base;
  `bpu_test_utils(random_pipeline_coherent_test, "16.1")

  virtual task test_body();
    int n_fetch_b, n_fetch_c;
    make_gen(32'd2);                      // seed co dinh -> tai lap duoc

    phase_of("A_1000_random_branches");
    gen.run_random_branches(.n(1000), .b2b(1'b1));
    `uvm_info(test_label, {"sau pha A: ", gen.stats()}, UVM_LOW)

    phase_of("B_2000_random_ctrl_cycles");
    gen.run_random_ctrl(.n_cyc(2000));
    n_fetch_b = gen.n_fetch_wins;
    `uvm_info(test_label, {"sau pha B: ", gen.stats()}, UVM_LOW)
    chk(gen.n_flush3_cycles > 0, "khong chu ky nao lai flush_in=3 -- gia tri 3 phai duoc phu");
    chk(gen.n_halt_cycles > 0, "khong chu ky nao lai halt=1");

    // reference model xoa shadow khi thay negedge rst_n nen scoreboard van song
    phase_of("C_reset_injection_and_recovery");
    gen.inject_reset(.n_cyc_held(3));
    gen.run_random_branches(.n(200), .b2b(1'b0));
    n_fetch_c = gen.n_fetch_wins;
    `uvm_info(test_label, {"sau pha C: ", gen.stats()}, UVM_LOW)
    chk(n_fetch_c > n_fetch_b, "sau reset khong con chu ky nao tang fetch thang -- BPU khong hoi phuc");
  endtask

  // TU KIEM hai tang:
  //  (1) bat bien nxpc2(T) == nxpc(T+1) == pc(T+2) doc tu net interface (phep
  //      kiem CHINH, gen_final_checks dem so vi pham);
  //  (2) tang fetch co hoat dong: f_valid && !d_valid && !corr_valid > 0 (chi la
  //      phep kiem song: mot dia chi co dinh sau mot luc cung thanh o BTB hop le).
  function void report_phase(uvm_phase phase);
    real n = real'(gen.n_cycles_sampled);
    phase_of("SELFCHECK_pipeline_coherence");
    chk(gen.n_coherence_checked > 0, "khong bo ba (nxpc2,nxpc,pc) nao duoc doi chieu -- bo sinh khong day nhanh nao qua duong ong");
    phase_of("SELFCHECK_fetch_tier_exercised");
    chk(gen.n_fetch_wins > 0, "tang FETCH chua bao gio thang MUX -- kich thich khong kich hoat duoc duong du doan tai tang fetch");
    chk(gen.n_btb_valid_nxpc2 > 0, "btb_valid_nxpc2 chua bao gio bang 1 -- duong doc BTB phia du doan khong duoc kich hoat");
    if (n > 0)
      note($sformatf("phan bo MUX: fetch=%.1f%% decode=%.1f%% corr=%.1f%% none=%.1f%% (tren %0d chu ky)",
                     100.0 * gen.n_fetch_wins / n, 100.0 * gen.n_decode_wins / n,
                     100.0 * gen.n_corr_wins / n, 100.0 * gen.n_no_redirect / n, gen.n_cycles_sampled));
    phase_of("FINAL_robustness");
    chk_no_miscompare(2500);
    super.report_phase(phase);
  endfunction
endclass : random_pipeline_coherent_test


//==============================================================================
// 16.2 stress_long_run
//
// Sheet -- Flow: chuoi 10.000 nhanh tron mau (luon-re / xen ke / tuong quan /
//   cold-start) tren bo sinh nhat quan duong ong.
// Sheet Performance chi so E -- DIEM DO: ti le BTB trung do o btb_valid_nxpc2
//   (PHIA DU DOAN, quyet dinh f_valid) chu khong phai btb_valid_pc (phia cap
//   nhat, reference dem). Hai con so o hai chi muc, hai thoi diem khac nhau.
//
//   SO DO (seed 2, 10.000 nhanh): btb_valid_nxpc2 = 98.3%. Nguong 95%: chiu
//   duoc thay doi nho o ti le tron mau, van bat duoc suy giam that.
//==============================================================================
class stress_long_run_hyb_test extends bpu_scene_base;
  `bpu_test_utils(stress_long_run_hyb_test, "16.2")

  localparam int  NUM         = 10000;
  localparam real BTB_HIT_MIN = 95.0;

  virtual task test_body();
    int n = 0;
    bit a;
    make_gen(32'd2);

    phase_of("A_mixed_10k");
    while (n < NUM) begin
      for (int i = 0; i < 20 && n < NUM; i++) begin                       // khoi luon-re
        gen.push_branch(.pc(32'h0000_0100), .taken(1'b1)); n++; end
      for (int i = 0; i < 20 && n < NUM; i++) begin                       // khoi xen ke
        gen.push_branch(.pc(32'h0000_0200), .taken(n % 2 == 0)); n++; end
      for (int i = 0; i < 10 && n < NUM; i++) begin                       // khoi tuong quan: B = A
        a = gen.rnd_bit();
        gen.push_branch(.pc(32'h0000_0300), .taken(a)); n++;
        if (n >= NUM) break;
        gen.push_branch(.pc(32'h0000_0400), .taken(a)); n++; end
      if (n < NUM) begin                                                  // mot nhanh cold-start
        gen.push_branch(.pc(32'h0000_0800 + ((n % 256) << 2)), .taken(1'b1)); n++; end
    end
    gen.drain();
  endtask

  function void report_phase(uvm_phase phase);
    bpu_reference r = tb.module_env.reference;
    real hit_rate_nxpc2 = bpu_pct(gen.n_btb_valid_nxpc2, gen.n_cycles_sampled);
    real hit_rate_pc    = bpu_pct(r.btb_hits_at_branch, r.total_branches);
    phase_of("REPORT_btb_hit_rate_fetch_side");
    note($sformatf(
      {"\n=== 16.2 TI LE BTB TRUNG, HAI DIEM DO ===\n",
       "  phia DU DOAN  btb_valid_nxpc2 : %0d/%0d chu ky = %.1f%%   <-- chi so E\n",
       "  phia CAP NHAT btb_valid_pc    : %0d/%0d nhanh  = %.1f%%   (reference, de doi chieu)\n",
       "========================================"},
      gen.n_btb_valid_nxpc2, gen.n_cycles_sampled, hit_rate_nxpc2,
      r.btb_hits_at_branch, r.total_branches, hit_rate_pc));
    chk(hit_rate_nxpc2 >= BTB_HIT_MIN, $sformatf("ti le BTB trung phia du doan %.1f%% < %.1f%%", hit_rate_nxpc2, BTB_HIT_MIN));
    phase_of("FINAL_robustness");
    chk_no_miscompare(9000);
    super.report_phase(phase);
  endfunction
endclass : stress_long_run_hyb_test


//==============================================================================
// 16.3 stress_btb_full
//
// Sheet -- Flow: lap day 1024 entry BTB, roi 500 lan truy cap trung chi muc.
// Sheet -- Pass: du 1024 entry hop le; entry bi trung (idx 0..499) duoc thay
//   bang target moi; entry con lai (500..1023) giu nguyen.
//==============================================================================
class stress_btb_full_test extends bpu_scene_base;
  `bpu_test_utils(stress_btb_full_test, "16.3")

  virtual task test_body();
    int n_valid = 0, n_bad_repl = 0, n_bad_keep = 0;
    bit [31:0] exp;

    phase_of("A_fill_1024_then_alias_500");
    for (int i = 0; i < 1024; i++) drive_branch(i << 2, 1'b1, 32'h40);            // target = i*4 + 0x40
    for (int i = 0; i < 500;  i++) drive_branch((1024 + i) << 2, 1'b1, 32'h80);   // idx i lai, target moi

    phase_of("B_check");
    for (int i = 0; i < 1024; i++) if (bd.read_btb_valid(i) === 1'b1) n_valid++;
    chk(n_valid == 1024, $sformatf("chi %0d/1024 entry BTB hop le sau khi lap day", n_valid));
    for (int i = 0; i < 500; i++) begin
      exp = ((1024 + i) << 2) + 32'h80;
      if (bd.read_btb_target(i) !== exp) n_bad_repl++;
    end
    chk(n_bad_repl == 0, $sformatf("%0d entry trung chi muc KHONG duoc thay dung", n_bad_repl));
    for (int i = 500; i < 1024; i++) begin
      exp = (i << 2) + 32'h40;
      if (bd.read_btb_target(i) !== exp) n_bad_keep++;
    end
    chk(n_bad_keep == 0, $sformatf("%0d entry khong trung chi muc KHONG duoc giu nguyen", n_bad_keep));
    note($sformatf("valid=%0d/1024  replaced_ok=%0d/500  preserved_ok=%0d/524", n_valid, 500 - n_bad_repl, 524 - n_bad_keep));
  endtask
endclass : stress_btb_full_test
