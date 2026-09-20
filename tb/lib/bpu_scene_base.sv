//------------------------------------------------------------------------------
// FILE: lib/bpu_scene_base.sv
//
// CLASS: bpu_scene_base -- cac CANH DUNG (scenario) dung chung, xay tren cac
// nguyen thuy cua bpu_test_base. Moi test ke thua lop nay.
//
// Muc luc:
//   1. Ba dia chi chuan TK / NT / UT    : setup_addresses(), refresh_tk/nt()
//   2. Canh carry-down (14.2)           : carry_set_scene(), carry_clear_scene()
//   3. Canh bo chon tournament (nhom 6) : build_choice_scene(), assert_choice_scene(),
//                                         choice_step()
//   4. Nhanh dau tien sau reset (1.2)   : first_branch_backstop(), check_first_branch()
//   5. Mau re nhanh (nhom 15)           : run_pattern(), run_loop(), tally(), show_tally()
//------------------------------------------------------------------------------

class bpu_scene_base extends bpu_test_base;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  //==========================================================================
  // SECTION 1: BA DIA CHI CHUAN
  //   TK = 0x100 : BTB hop le + du doan RE       -> hit=1, f_valid=1
  //   NT = 0x200 : BTB hop le + du doan KHONG RE -> hit=1, f_valid=0
  //   UT = 0x300 : chua bao gio duoc ghi         -> hit=0, f_valid=0
  //   Thu tu quan trong: TK truoc (ket thuc o chi muc 0xFFF) roi moi den NT
  //   (dung chi muc 0), vi nhanh DAU TIEN cua moi dia chi deu ghi local_pht[0].
  //==========================================================================

  // Goi MOT LAN o dau moi muc.
  protected task automatic setup_addresses();
    train_predict_taken(ADDR_TK, 24);
    train_predict_not_taken(ADDR_NT, 8);
    chk(bd.read_btb_valid(bpu_idx(ADDR_TK)) === 1'b1, "chuan bi: btb_valid[TK] phai = 1");
    chk(bd.read_btb_valid(bpu_idx(ADDR_NT)) === 1'b1, "chuan bi: btb_valid[NT] phai = 1");
    chk(bd.read_btb_valid(bpu_idx(ADDR_UT)) === 1'b0, "chuan bi: btb_valid[UT] phai = 0");
  endtask

  // Huan luyen lai NT: BAT KY nhanh moi nao o dia chi la cung ghi local_pht[0]
  // (lich su con 0) -- dung o ma du doan cua NT doc -> NT co the thanh "RE".
  protected task automatic refresh_nt();
    train_predict_not_taken(ADDR_NT, 6);
  endtask

  // Huan luyen lai TK sau bat ky nhanh NOT-TAKEN nao tai ADDR_TK.
  protected task automatic refresh_tk();
    train_predict_taken(ADDR_TK, 24);
  endtask

  //==========================================================================
  // SECTION 2: CANH CARRY-DOWN (14.2) -- BTB trung tai A, choice chon LOCAL,
  //   hai bit du doan local/global dat theo y.
  //   Cac BANG dung DEPOSIT (giua set va diem quan sat khong co lenh ghi nao
  //   cua DUT). GHR phai FORCE: chi muc gshare la pc_index ^ ghr, nhanh cua to
  //   hop truoc se dich ghr va lam duong global doc nham o.
  //==========================================================================
  localparam bit [31:0] CARRY_A_PC  = 32'h0000_0100;   // idx 64
  localparam int        CARRY_A_IDX = 64;
  localparam bit [31:0] CARRY_A_TGT = 32'h0000_1234;   // btb_target[64] duoc ep
  localparam int        CARRY_L_IDX = 12'h345;         // chi muc local_pht duoc ghim

  protected task automatic carry_set_scene(bit loc_bit, bit glb_bit);
    bd.deposit_btb(CARRY_A_IDX, 1'b1, CARRY_A_TGT);
    bd.force_ghr(10'd0);                                  // chi muc global = A_IDX
    bd.deposit_choice(CARRY_A_IDX, `WNT);                 // choice[1]=0 -> chon local
    bd.deposit_local_bht(CARRY_A_IDX, CARRY_L_IDX[11:0]); // chi muc local_pht = L_IDX
    bd.deposit_local_pht(CARRY_L_IDX, loc_bit ? `ST : `SNT);
    bd.deposit_global_pht(CARRY_A_IDX, glb_bit ? `ST : `SNT);
  endtask

  protected task automatic carry_clear_scene();
    bd.release_ghr();
  endtask

  //==========================================================================
  // SECTION 3: CANH BO CHON TOURNAMENT (nhom 6)
  //
  //   bpu_predictor.v so local_carry voi global_carry: hai bit du doan doc tai
  //   nxpc2 o THOI DIEM FETCH, mang xuong hai chu ky. Canh duoi day dung HOAN
  //   TOAN bang duong cap nhat that, dua he thong toi GHR = 0 va bon dia chi
  //   cho dung bon to hop (local_carry, global_carry) khi doc tai nxpc2:
  //
  //     R_00 = 0x0800 -> local_pht[1024]=SNT , global_pht[512]=SNT  -> (0,0)
  //     R_01 = 0x0900 -> local_pht[   5]=SNT , global_pht[576]=WT   -> (0,1)
  //     R_10 = 0x0400 -> local_pht[   0]=WT  , global_pht[256]=SNT  -> (1,0)
  //     R_11 = 0x0300 -> local_pht[   0]=WT  , global_pht[192]=WT   -> (1,1)
  //
  //   ADDR_P = 0x0C00 (idx 768) la dia chi GHI: choice[768] la thu duoc do. No
  //   co btb_valid=1 va bht=0xFFF nen nhanh khong re tai do chi ghi local_pht o
  //   vung chi muc cao, khong cham bon o ma bon dia chi R dang doc.
  //==========================================================================
  localparam bit [31:0] R_00 = 32'h0000_0800;   // idx 512
  localparam bit [31:0] R_01 = 32'h0000_0900;   // idx 576
  localparam bit [31:0] R_10 = 32'h0000_0400;   // idx 256
  localparam bit [31:0] R_11 = 32'h0000_0300;   // idx 192

  localparam bit [31:0] ADDR_P  = 32'h0000_0C00;   // idx 768 -- muc tieu chinh
  localparam bit [31:0] ADDR_P2 = 32'h0000_0500;   // idx 320 -- doc lap voi P
  localparam bit [31:0] ADDR_PA = 32'h0000_1C00;   // idx 768 -- TRUNG chi muc voi P
  localparam bit [31:0] ADDR_NB = 32'h0000_0700;   // idx 448 -- KHONG co btb_valid
  localparam int P_IDX  = 768;
  localparam int P2_IDX = 320;
  localparam int NB_IDX = 448;

  // Dung lai canh tu dau. BAT DAU BANG RESET: chuoi huan luyen chi cho dung ket
  // qua khi may o trang thai sach (nhanh dau tai dia chi la ghi THANG WT, va
  // local_bht xuat phat tu 0 moi chay dung day 1,2,4,...).
  // Thu tu: ADDR_P truoc R_01, vi huan luyen ADDR_P lam local_bht chay qua
  // 1,3,7,... va se ghi de o local_pht ma R_01 dinh doc neu lam nguoc lai.
  protected task automatic build_choice_scene();
    bus_free();
    apply_idle(2);        // is_branch = 0 truoc khi assert reset (gioi han reference)
    bus_free();
    reset_by_force(3);
    repeat (24) drive_branch(ADDR_TK, 1'b1, 32'h40);   // bht[64]=0xFFF
    repeat (6)  drive_branch(ADDR_NT, 1'b0, 32'h40);
    repeat (24) drive_branch(ADDR_P,  1'b1, 32'h40);   // bht[768]=0xFFF, btb_valid=1
    repeat (24) drive_branch(ADDR_P2, 1'b1, 32'h40);   // bht[320]=0xFFF, btb_valid=1
    warm_cycle(32'h0000_0800);                         // GHR -> 0, local_pht[0] = WT
    drive_branch(R_01, 1'b1, 32'h40);                  // bht[576]: 0 -> 1
    drive_branch(R_01, 1'b0, 32'h40);                  // bht[576]: 1 -> 2
    drive_branch(R_01, 1'b1, 32'h40);                  // bht[576]: 2 -> 5 (o chua ai ghi)
    warm_cycle(32'h0000_0A00);                         // GHR -> 0
  endtask

  // Kiem TIEN DE: dia chi R that su cho dung to hop (local, global) mong doi.
  protected task automatic assert_carry(string lbl, bit [31:0] R, bit exp_l, bit exp_g);
    bpu_fetch_obs_t o;
    observe_at(R, 2'd0, o);
    chk(o.lp[1] === exp_l, $sformatf(
      "%s: nxpc2=0x%08h cho local_pht_data_nxpc2[1]=%0d (%02b), canh dung SAI (can %0d)",
      lbl, R, o.lp[1], o.lp, exp_l));
    chk(o.gp[1] === exp_g, $sformatf(
      "%s: nxpc2=0x%08h cho global_pht_data_nxpc2[1]=%0d (%02b), canh dung SAI (can %0d)",
      lbl, R, o.gp[1], o.gp, exp_g));
  endtask

  protected task automatic assert_choice_scene(string lbl);
    assert_carry({lbl, " R_00"}, R_00, 1'b0, 1'b0);
    assert_carry({lbl, " R_01"}, R_01, 1'b0, 1'b1);
    assert_carry({lbl, " R_10"}, R_10, 1'b1, 1'b0);
    assert_carry({lbl, " R_11"}, R_11, 1'b1, 1'b1);
    chk(bd.read_btb_valid(P_IDX) === 1'b1, $sformatf(
      "%s: btb_valid[%0d] phai = 1 thi choice_wr_en moi co the tich cuc", lbl, P_IDX));
    chk(bd.read_ghr() === 10'd0, $sformatf(
      "%s: ghr=0x%03h, canh dung can 0 de chi muc global bang nxpc2_index", lbl, bd.read_ghr()));
  endtask

  // MOT lan cap nhat bo chon, lai tay tung chu ky:
  //   F   : nxpc2 = R  -> chot (local_carry, global_carry)
  //   F+1 : trung tinh, opcode ADDI -> d_valid = 0
  //   F+2 : pc = P, is_branch, branch_taken = taken; doc carry/wr_en NGAY tai day
  //   F+3 : mot chu ky nua de lenh ghi tai canh len F+2 on dinh roi moi doc choice
  protected task automatic choice_step(input  bit [31:0] R,
                                       input  bit [31:0] P,
                                       input  bit        taken,
                                       input  int        cidx,
                                       output bit        lc,
                                       output bit        gc,
                                       output bit        wren,
                                       output bit [1:0]  ch_b,
                                       output bit [1:0]  ch_a,
                                       input  bit        is_branch = 1'b1);
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(R),         .opcode(OPC_NOP));
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP));
    ch_b = bd.read_choice(cidx);
    apply(.pc(P), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .btf(32'h0), .flush_in(2'd0), .halt(1'b0),
          .is_branch(is_branch), .taken(taken), .offset(32'h40));
    lc   = bd.read_local_carry();
    gc   = bd.read_global_carry();
    wren = bd.read_choice_wr_en();
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP));
    ch_a = bd.read_choice(cidx);
  endtask

  //==========================================================================
  // SECTION 4: NHANH DAU TIEN SAU RESET (1.2) -- di theo duong backstop
  //   F   : nxpc2 = pc (BTB rong -> truot), tang decode con trong
  //   F+1 : nxpc = pc, fetch_opcode = BCC, BTB van truot -> backstop lai
  //   F+2 : nhanh toi execute, thuc su re
  //==========================================================================
  protected task automatic first_branch_backstop(input  bit [31:0] pc, input bit [31:0] btf,
                                                 output bpu_fetch_obs_t oF,
                                                 output bpu_fetch_obs_t oD,
                                                 output bpu_fetch_obs_t oX);
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(pc), .opcode(OPC_NOP), .btf(32'h0));
    oF = snap();
    apply(.pc(NEU_PC), .nxpc(pc), .nxpc2(NEU_NXPC2), .opcode(OPC_BR), .btf(btf));
    oD = snap();
    apply(.pc(pc), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .btf(32'h0), .is_branch(1'b1), .taken(1'b1), .offset(32'h40));
    oX = snap();
  endtask

  protected function void check_first_branch(string tag, bit [31:0] pc, bit [31:0] btf,
                                             bpu_fetch_obs_t oF, bpu_fetch_obs_t oD,
                                             bpu_fetch_obs_t oX);
    chk(oF.fv   === 1'b0, $sformatf("%s (F): f_valid=%0d, ky vong 0 (BTB rong tai nxpc2)", tag, oF.fv));
    chk(oF.outv === 1'b0, $sformatf("%s (F): bpu_nxpc2_valid=%0d, ky vong 0", tag, oF.outv));
    chk(oD.dv   === 1'b1, $sformatf("%s (F+1): d_valid=%0d, ky vong 1 (BCC + BTB truot tai nxpc)", tag, oD.dv));
    chk(oD.fv   === 1'b0, $sformatf("%s (F+1): f_valid=%0d, ky vong 0", tag, oD.fv));
    chk(oD.outv === 1'b1, $sformatf("%s (F+1): bpu_nxpc2_valid=%0d, ky vong 1", tag, oD.outv));
    chk(oD.outp === (pc + btf),
        $sformatf("%s (F+1): bpu_nxpc2=0x%08h, ky vong 0x%08h (nxpc + branch_target_fetch)",
                  tag, oD.outp, pc + btf));
    chk(oX.fl   === 2'd1,
        $sformatf("%s (F+2): bpu_flush=%0d, ky vong 1 (BTB truot luc fetch + nhanh thuc su re)", tag, oX.fl));
  endfunction

  //==========================================================================
  // SECTION 5: MAU RE NHANH (nhom 15) -- chay tren bpu_coherent_gen
  //
  //   GAP: bang PHT/BHT/GHR chi duoc ghi o tang EXECUTE, tuc HAI chu ky sau khi
  //   nhanh duoc tra o fetch. Lai sat nhau thi bo du doan luon nhin trang thai
  //   cu hai nhanh (mau chu ky 5 sat nhau: 40% doan sai; GAP = 2: 0%). Nhom 15
  //   do CHAT LUONG DU DOAN nen tach hieu ung duong ong ra bang GAP = 2.
  //==========================================================================
  localparam int GAP = 2;

  // Lai mot chuoi mau tai mot PC, tra ve id de doi chieu ve sau.
  protected task automatic run_pattern(bit [31:0] pc, bit pat[], ref int ids[$]);
    foreach (pat[i]) begin
      gen.push_branch(.pc(pc), .taken(pat[i]));
      ids.push_back(gen.last_id);
      gen.idle(GAP);
    end
  endtask

  // n vong cua mot chu ky do dai `period` (period-1 lan RE roi 1 lan KHONG RE),
  // tra ve id cua cac nhanh SAU giai doan khoi dong.
  protected task automatic run_loop(bit [31:0] pc, int period, int warm_loops, int meas_loops,
                                    ref int ids[$]);
    for (int l = 0; l < warm_loops + meas_loops; l++)
      for (int i = 0; i < period; i++) begin
        gen.push_branch(.pc(pc), .taken((i != period - 1)));
        if (l >= warm_loops) ids.push_back(gen.last_id);
        gen.idle(GAP);
      end
  endtask

  // Dem ket qua theo tung nhanh. MISPREDICT dinh nghia GIONG reference model:
  // bpu_flush == 2 (doan sai huong); flush == 1 la BTB truot + re thuc, dem rieng.
  protected function bpu_flush_tally_t tally(int ids[$]);
    bpu_flush_tally_t t = '{default:0};
    foreach (ids[i]) begin
      bpu_pipe_obs_t o = gen.obs_of(ids[i]);
      t.n++;
      case (o.bpu_flush)
        2'd0: t.n_flush0++;
        2'd1: t.n_flush1++;
        2'd2: t.n_flush2++;
      endcase
    end
    return t;
  endfunction

  // Cac nhanh tu vi tri `from` tro di (bo giai doan hoc).
  protected function bpu_flush_tally_t tally_from(int ids[$], int from);
    int sub[$];
    for (int i = from; i < ids.size(); i++) sub.push_back(ids[i]);
    return tally(sub);
  endfunction

  protected function void show_tally(string tag, bpu_flush_tally_t t);
    note($sformatf("%-28s nhanh=%0d  flush0=%0d (%.1f%%)  flush1=%0d  flush2=%0d (%.1f%%)",
      tag, t.n, t.n_flush0, bpu_pct(t.n_flush0, t.n), t.n_flush1,
      t.n_flush2, bpu_pct(t.n_flush2, t.n)));
  endfunction

endclass : bpu_scene_base
