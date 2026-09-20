//------------------------------------------------------------------------------
// FILE: tests/t13_mux_tests.sv -- Nhom 13: Output MUX
//   13.1 mux_priority_and_valid
//------------------------------------------------------------------------------


//==============================================================================
// 13.1 mux_priority_and_valid
// Sheet -- Flow: du TAM to hop cua (corr_valid, d_valid, f_valid) voi ba dich
//   phan biet; bo sung truong hop ngay sau reset va halt khong co nhanh.
// Sheet -- Pass: bpu_nxpc2 theo uu tien hieu chinh > du phong > fetch;
//   bpu_nxpc2_valid = hop cua ba; khong nguon nao -> valid=0 va bpu_nxpc2 = 0.
// RTL Ref: bpu_ctrl.v
//
// Trong MOT chu ky, ba tang do BA nhanh khac nhau chi phoi: slot EXECUTE ->
// corr, DECODE -> d, FETCH -> f. Day ba nhanh lien tiep roi doc o chu ky thu ba.
//==============================================================================
class mux_priority_and_valid_test extends bpu_scene_base;
  `bpu_test_utils(mux_priority_and_valid_test, "13.1")

  localparam bit [31:0] PC_CORR_BASE = 32'h0000_0500;
  localparam bit [31:0] PC_D         = 32'h0000_0600;   // chua gap -> d_valid duoc
  localparam bit [31:0] CORR_TGT     = 32'hAAAA_0000;
  localparam bit [31:0] D_TGT        = 32'hBBBB_0000;
  bit [31:0] f_tgt;
  string     tbl;

  local task automatic run_cell(int idx, bit want_c, bit want_d, bit want_f, output bpu_pipe_obs_t o);
    bit [31:0] pc_c = PC_CORR_BASE + (idx * 32'h0000_0010);
    int base;
    h.idle(4);
    // B0 -> EXECUTE: nxpc2 = UT (hit=0, f=0), opcode ADDI (d=0) => predicted_taken=0, corr_valid = branch_taken
    h.push_branch(.pc(pc_c), .taken(want_c), .offset(CORR_TGT - pc_c), .opcode(OPC_NOP),
                  .is_branch(1'b1), .ovr_nxpc2(1'b1), .nxpc2(ADDR_UT));
    // B1 -> DECODE: quyet dinh d_valid
    h.push_branch(.pc(PC_D), .taken(1'b0), .offset(32'h40), .opcode(want_d ? OPC_BR : OPC_NOP),
                  .btf(D_TGT - PC_D), .is_branch(1'b0), .ovr_nxpc2(1'b1), .nxpc2(ADDR_UT));
    base = h.num_cycles();
    // B2 -> FETCH: quyet dinh f_valid
    h.push_branch(.pc(32'h0000_0610), .taken(1'b0), .offset(32'h40), .opcode(OPC_NOP),
                  .is_branch(1'b0), .ovr_nxpc2(1'b1), .nxpc2(want_f ? ADDR_TK : ADDR_UT));
    o = h.obs_at_cycle(base);
    h.drain();
  endtask

  local task automatic do_cell(int idx, bit c, bit d, bit f);
    bpu_pipe_obs_t o;
    bit [31:0] exp;
    string     src;
    run_cell(idx, c, d, f, o);
    if      (c) begin exp = CORR_TGT; src = "corr";     end
    else if (d) begin exp = D_TGT;    src = "backstop"; end
    else if (f) begin exp = f_tgt;    src = "fetch";    end
    else        begin exp = 32'd0;    src = "none";     end
    chk(o.bpu_nxpc2_valid === (c | d | f), $sformatf("(c=%0d d=%0d f=%0d): valid=%0d, ky vong %0d", c, d, f, o.bpu_nxpc2_valid, (c | d | f)));
    chk(o.bpu_nxpc2 === exp, $sformatf("(c=%0d d=%0d f=%0d): nxpc2=0x%08h, ky vong 0x%08h (nguon %s)", c, d, f, o.bpu_nxpc2, exp, src));
    tbl = {tbl, $sformatf("  |  %0d  | %0d | %0d | %0d | 0x%08h | %s\n", c, d, f, o.bpu_nxpc2_valid, o.bpu_nxpc2, src)};
  endtask

  virtual task test_body();
    bpu_pipe_obs_t o;

    //---- A: ngay sau reset -> khong nguon nao tich cuc ----------------------
    phase_of("A_right_after_reset");
    chk(bd.read_bpu_nxpc2_valid() === 1'b0,  "ngay sau reset: bpu_nxpc2_valid != 0");
    chk(bd.read_bpu_nxpc2()       === 32'd0, "ngay sau reset: bpu_nxpc2 != 0");

    setup_addresses();
    f_tgt = bd.read_btb_target(bpu_idx(ADDR_TK));
    tbl = "";

    //---- B: du TAM to hop (corr, d, f) --------------------------------------
    phase_of("B_eight_combinations");
    for (int i = 0; i < 8; i++) do_cell(i, i[2], i[1], i[0]);
    note($sformatf({
      "\n===== MUX: uu tien corr > backstop > fetch =====\n",
      "  | c | d | f | vld |   bpu_nxpc2   | nguon thang\n",
      "  |---|---|---|-----|---------------|-------------\n", "%s",
      "  corr_tgt=0x%08h  d_tgt=0x%08h  f_tgt=0x%08h\n",
      "==============================================="}, tbl, CORR_TGT, D_TGT, f_tgt));

    //---- C: halt, khong co nhanh -> khong chuyen huong ----------------------
    phase_of("C_halt_no_branch");
    h.idle(4);
    h.idle(3, 2'd0, 1'b1);            // ba chu ky halt=1, khong nhanh
    o = h.obs_at_cycle(h.num_cycles() - 1);
    chk(o.bpu_nxpc2_valid === 1'b0,  $sformatf("halt khong nhanh: valid=%0d, ky vong 0", o.bpu_nxpc2_valid));
    chk(o.bpu_nxpc2       === 32'd0, $sformatf("halt khong nhanh: nxpc2=0x%08h, ky vong 0", o.bpu_nxpc2));
  endtask
endclass : mux_priority_and_valid_test
