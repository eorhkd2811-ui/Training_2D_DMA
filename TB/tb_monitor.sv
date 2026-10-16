`timescale 1ns/1ps
// Passive edge-based AXI monitor. +MONITOR enables per-transfer $display logs.
module tb_monitor(tb_if bus);
  bit verbose;

  initial verbose=$test$plusargs("MONITOR");

  always @(posedge bus.aclk) if(bus.aresetn && verbose) begin
    if(bus.s_awvalid_i && bus.s_awready_o) $display("[MON][CSR AW] t=%0t id=%h addr=%h len=%0d size=%0d",$time,bus.s_awid_i,bus.s_awaddr_i,bus.s_awlen_i,bus.s_awsize_i);
    if(bus.s_wvalid_i && bus.s_wready_o) $display("[MON][CSR W] t=%0t data=%h strb=%h last=%b",$time,bus.s_wdata_i,bus.s_wstrb_i,bus.s_wlast_i);
    if(bus.s_bvalid_o && bus.s_bready_i) $display("[MON][CSR B] t=%0t id=%h resp=%h",$time,bus.s_bid_o,bus.s_bresp_o);
    if(bus.s_arvalid_i && bus.s_arready_o) $display("[MON][CSR AR] t=%0t id=%h addr=%h",$time,bus.s_arid_i,bus.s_araddr_i);
    if(bus.s_rvalid_o && bus.s_rready_i) $display("[MON][CSR R] t=%0t id=%h data=%h resp=%h last=%b",$time,bus.s_rid_o,bus.s_rdata_o,bus.s_rresp_o,bus.s_rlast_o);
    if(bus.m_arvalid_o && bus.m_arready_i) $display("[MON][AR] t=%0t id=%h addr=%h len=%0d size=%0d",$time,bus.m_arid_o,bus.m_araddr_o,bus.m_arlen_o,bus.m_arsize_o);
    if(bus.m_rvalid_i && bus.m_rready_o) $display("[MON][R] t=%0t id=%h data=%h last=%b",$time,bus.m_rid_i,bus.m_rdata_i,bus.m_rlast_i);
    if(bus.m_awvalid_o && bus.m_awready_i) $display("[MON][AW] t=%0t id=%h addr=%h len=%0d",$time,bus.m_awid_o,bus.m_awaddr_o,bus.m_awlen_o);
    if(bus.m_wvalid_o && bus.m_wready_i) $display("[MON][W] t=%0t data=%h last=%b",$time,bus.m_wdata_o,bus.m_wlast_o);
    if(bus.m_bvalid_i && bus.m_bready_o) $display("[MON][B] t=%0t id=%h resp=%h",$time,bus.m_bid_i,bus.m_bresp_i);
  end
endmodule
