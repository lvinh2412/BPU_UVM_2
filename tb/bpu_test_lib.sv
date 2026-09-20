//------------------------------------------------------------------------------
// FILE: bpu_test_lib.sv
//
// CLASS: bpu_base_test -- tao testbench, khong lam gi khac.
//
// Cay ke thua cua moi test:
//   bpu_base_test      (tep nay)             tao bpu_tb, drain time
//   bpu_test_base      (lib/bpu_test_base.sv) nguyen thuy: chk, drive, apply, reset...
//   bpu_scene_base     (lib/bpu_scene_base.sv) canh dung: dia chi chuan, choice, pattern
//   <ten_test>         (tests/tNN_*.sv)        chi con test_body()
//------------------------------------------------------------------------------

class bpu_base_test extends uvm_test;

  `uvm_component_utils(bpu_base_test)

  bpu_tb tb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  function void build_phase(uvm_phase phase);
    uvm_config_int::set(this, "*", "recording_detail", 1);
    super.build_phase(phase);
    tb = bpu_tb::type_id::create("tb", this);
  endfunction : build_phase

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction : end_of_elaboration_phase

  function void start_of_simulation_phase(uvm_phase phase);
    `uvm_info(get_type_name(), {"start of simulation for ", get_full_name()}, UVM_HIGH);
  endfunction : start_of_simulation_phase

  task run_phase(uvm_phase phase);
    // Drain time de duong ong chuyen huong va mo hinh tham chieu chay het nhung chu
    // ky con dang do sau khi sequence cuoi cung ha objection
    uvm_objection obj = phase.get_objection();
    obj.set_drain_time(this, 2000ns);
  endtask : run_phase

  function void check_phase(uvm_phase phase);
    // Bao cac muc config_db khong ai doc -- thuong la go sai chuoi scope
    check_config_usage();
  endfunction

endclass : bpu_base_test


//==============================================================================
// Thu vien test dung chung
//==============================================================================
`include "bpu_test_base.sv"
`include "bpu_scene_base.sv"

//==============================================================================
// 44 muc cua BPU_Testplan_Hybrid_44.xlsx, moi tep = mot nhom cua sheet TestCase
//==============================================================================
`include "tests/t01_reset_tests.sv"        // 1.1 - 1.2   Reset & Init
`include "tests/t02_halt_tests.sv"         // 2.1 - 2.2   Halt
`include "tests/t03_btb_tests.sv"          // 3.1 - 3.3   BTB
`include "tests/t04_local_pht_tests.sv"    // 4.1 - 4.4   Local PHT (Pshare)
`include "tests/t05_global_pht_tests.sv"   // 5.1 - 5.4   Global PHT (Gshare)
`include "tests/t06_choice_tests.sv"       // 6.1 - 6.4   Choice
`include "tests/t07_ghr_tests.sv"          // 7.1         GHR
`include "tests/t08_predict_tests.sv"      // 8.1 - 8.2   Du doan tai tang fetch
`include "tests/t09_precompute_tests.sv"   // 9.1         Pre-compute & Gating
`include "tests/t10_flush_tests.sv"        // 10.1 - 10.2 Flush Logic
`include "tests/t11_redirect_tests.sv"     // 11.1 - 11.3 Tang chuyen huong
`include "tests/t12_correction_tests.sv"   // 12.1 - 12.2 Correction
`include "tests/t13_mux_tests.sv"          // 13.1        Output MUX
`include "tests/t14_carry_tests.sv"        // 14.1 - 14.4 Carry-down pipeline
`include "tests/t15_pattern_tests.sv"      // 15.1 - 15.6 Branch Pattern
`include "tests/t16_stress_tests.sv"       // 16.1 - 16.3 Stress / Random
