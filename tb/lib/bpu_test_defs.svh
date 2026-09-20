//------------------------------------------------------------------------------
// FILE: lib/bpu_test_defs.svh
//
// Dinh nghia dung chung cho TOAN BO test: macro, kieu du lieu va cac ham thuan
// (khong ton thoi gian mo phong, khong cham DUT). Duoc include mot lan trong
// bpu_tb_top truoc moi tep khac.
//------------------------------------------------------------------------------
`ifndef BPU_TEST_DEFS_SVH
`define BPU_TEST_DEFS_SVH

//------------------------------------------------------------------------------
// Bon trang thai cua bo dem bao hoa 2 bit (local_pht / global_pht / choice)
//------------------------------------------------------------------------------
`define SNT 2'b00
`define WNT 2'b01
`define WT  2'b10
`define ST  2'b11

//------------------------------------------------------------------------------
// Khai bao mot test: dang ky factory + constructor + ma muc trong testplan.
//
//   class btb_write_and_target_test extends bpu_scene_base;
//     `bpu_test_utils(btb_write_and_target_test, "3.1")
//     virtual task test_body(); ... endtask
//   endclass
//
// Phan con lai (chon clock, tao helper, raise/drop objection, cho reset xong,
// bao cao PASS/FAIL) do bpu_test_base lam.
//------------------------------------------------------------------------------
`define bpu_test_utils(T, ID) \
  `uvm_component_utils(T) \
  function new(string name, uvm_component parent); \
    super.new(name, parent); \
    test_id = ID; \
  endfunction

//------------------------------------------------------------------------------
// Anh chup MOT chu ky nhin tu tang FETCH (doc bang backdoor ngay sau apply()).
//------------------------------------------------------------------------------
typedef struct {
  bit        hit;      // btb_valid_nxpc2       (bpu_reg.v)
  bit [1:0]  lp;       // local_pht_data_nxpc2  (bpu_reg.v)
  bit [1:0]  gp;       // global_pht_data_nxpc2 (bpu_reg.v)
  bit [1:0]  ch;       // choice_data_nxpc2     (bpu_reg.v)
  bit        pt;       // predict_taken_nxpc2   (bpu_predictor.v)
  bit [31:0] tgt;      // btb_target_nxpc2      (bpu_reg.v)
  bit        fib;      // fetch_is_branch       (bpu_ctrl.v)
  bit        fr;       // fetch_ready           (bpu_ctrl.v)
  bit        fv;       // f_valid               (bpu_ctrl.v)
  bit        dv;       // d_valid               (bpu_ctrl.v)
  bit        cv;       // corr_valid            (bpu_ctrl.v)
  bit [31:0] outp;     // bpu_nxpc2
  bit        outv;     // bpu_nxpc2_valid
  bit [1:0]  fl;       // bpu_flush
} bpu_fetch_obs_t;

//------------------------------------------------------------------------------
// Tam thanh ghi carry-down (bpu_ctrl.v), theo thu tu:
//   [0..3] tang 1 : predic_taken_delay_1, btb_hit_delay_1, local_delay_1, global_delay_1
//   [4..7] tang 2 : predic_taken_delay_2, btb_hit_delay_2, local_delay_2, global_delay_2
//------------------------------------------------------------------------------
typedef bit bpu_carry_regs_t[8];

//------------------------------------------------------------------------------
// Thong ke bpu_flush theo tung nhanh (nhom 15 / 16)
//------------------------------------------------------------------------------
typedef struct {
  int n;          // so nhanh da xet
  int n_flush0;   // doan dung, khong bong bong
  int n_flush1;   // BTB truot + re thuc
  int n_flush2;   // doan sai
} bpu_flush_tally_t;

//------------------------------------------------------------------------------
// Ham thuan
//------------------------------------------------------------------------------

// Bo dem bao hoa 2 bit -- ban sao cua bpu_predictor.v, de tinh ky vong CHINH
// XAC (ke ca o hai dau day) thay vi chi doi hoi "tang" hay "giam".
function automatic bit [1:0] bpu_upd_ctr(bit [1:0] cur, bit taken);
  case (cur)
    `ST     : return taken ? `ST  : `WT ;
    `WT     : return taken ? `ST  : `WNT;
    `WNT    : return taken ? `WT  : `SNT;
    default : return taken ? `WNT : `SNT;   // SNT
  endcase
endfunction

// Ky vong cho MOT lan cap nhat bo chon (bpu_predictor.v):
//   khong du dieu kien ghi hoac local == global -> giu nguyen
//   nguoc lai -> tien ve phia bo du doan trung voi branch_taken
function automatic bit [1:0] bpu_exp_choice(bit [1:0] cur, bit l, bit g, bit taken, bit wr_ok);
  if (!wr_ok || (l === g)) return cur;
  return bpu_upd_ctr(cur, (g === taken) ? 1'b1 : 1'b0);
endfunction

// Ten trang thai bo dem, de in log
function automatic string bpu_ctr_name(bit [1:0] v);
  case (v)
    2'b00: return "SNT";
    2'b01: return "WNT";
    2'b10: return "WT ";
    default: return "ST ";
  endcase
endfunction

// a/b theo phan tram; 0.0 neu b = 0
function automatic real bpu_pct(int a, int b);
  return (b > 0) ? 100.0 * real'(a) / real'(b) : 0.0;
endfunction

// Chi muc bang 10 bit tu dia chi: pc[11:2]
function automatic int bpu_idx(bit [31:0] a);
  return (a >> 2) & 32'h3FF;
endfunction

`endif // BPU_TEST_DEFS_SVH
