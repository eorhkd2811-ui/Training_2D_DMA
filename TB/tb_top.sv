`timescale 1ns/1ps
module tb_top;
  import tb_var::*;
  tb_if bus();
  tb_duv duv(bus);
  tb_drv driver(bus);
  tb_seq seq(bus);
  tb_monitor monitor(bus);
  tb_sb scoreboard(bus);
  initial begin bus.aclk=0; forever #(DUT_CLK_PERIOD/2.0) bus.aclk=~bus.aclk; end
  initial begin
    bus.aresetn=0;
    repeat(6) @(negedge bus.aclk);
    bus.aresetn=1;
  end
endmodule
