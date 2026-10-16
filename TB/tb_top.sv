`timescale 1ns/1ps
module tb_top;
  import tb_var::*;
  tb_if bus();
  tb_duv duv(bus);
  tb_drv driver(bus);
  tb_seq seq(bus);
  tb_monitor monitor(bus);
  tb_sb scoreboard(bus);
  // Read-only probes. No force/release, hierarchical assignment, or RTL edit.
  tb_wvalid_check wvalid_check(
    .bus(bus),
    .data_available(duv.dut.dm.wh.DST_AXI4_GEN.w.atx_wdata_vld),
    .len_available(duv.dut.dm.wh.DST_AXI4_GEN.w.wdata_len_vld),
    .data_ready(duv.dut.dm.wh.DST_AXI4_GEN.w.atx_wdata_rdy)
  );
  initial if($test$plusargs("DUMP_WAVE")) begin
    $dumpfile("wave.vcd"); $dumpvars(0,tb_top);
  end
  initial begin bus.aclk=0; forever #(DUT_CLK_PERIOD/2.0) bus.aclk=~bus.aclk; end
  initial begin
    bus.aresetn=0;
    repeat(6) @(negedge bus.aclk);
    bus.aresetn=1;
  end
endmodule
