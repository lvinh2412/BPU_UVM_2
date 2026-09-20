module bpu_tb_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import bpu_pkg::*;
  import clock_and_reset_pkg::*;
  import bpu_module_pkg::*;

  // Ha tang dung chung (lib/), theo thu tu phu thuoc
  `include "bpu_test_defs.svh"      // macro, kieu du lieu, ham thuan
  `include "bpu_drive_vseqs.sv"     // sequence mot nhanh / nghi
  `include "bpu_pipe_helper.sv"     // day nhanh qua ba tang, tu chup quan sat
  `include "bpu_det_rng.sv"         // nguon bit tat dinh
  `include "bpu_coherent_gen.sv"    // bo sinh ngau nhien nhat quan duong ong
  `include "bpu_tb.sv"              // moi truong muc cao nhat
  `include "bpu_test_lib.sv"        // base test + danh sach test

  initial begin
    bpu_vif_config::set(null, "*.tb.bpu.tx_agent.*", "vif",
                        bpu_hw_top.bpu_if);

    clock_and_reset_vif_config::set(null, "*.tb.clock_and_reset*", "vif",
                                    bpu_hw_top.clk_rst_if);

    uvm_config_db#(virtual clock_and_reset_if)::set(null,
                   "*.tb.module_env.reference", "rst_vif",
                   bpu_hw_top.clk_rst_if);

    run_test();
  end

endmodule
