`timescale 1ns/1ps
// Directed progress check plus a protocol hold check. The 32-cycle limit is a
// TB diagnostic bound, NOT an AXI-specified maximum VALID assertion latency.
// Data/length inputs are read-only DUT probes; only the Slave BFM drives READY.
module tb_wvalid_check(tb_if bus, input logic data_available,
                      input logic len_available, input logic data_ready);
  int limit_cycles=32;
  int blocked_cycles=0, cycle=0, aw_count=0, r_count=0, w_count=0, b_count=0;
  int offered_low_ready_cycles=0, valid_low_ready_cycles=0;
  int fd;
  bit previous_stall=0;
  logic [tb_var::ATX_DST_DATA_W+tb_var::ATX_DST_BYTE_AMT:0] previous_payload;
  initial begin
    if($value$plusargs("WVALID_TIMEOUT_CYCLES=%d",limit_cycles)) begin end
    if(limit_cycles<2 || limit_cycles>10000) $fatal(1,"[WCHK_SETUP] invalid timeout");
    fd=$fopen("wvalid_trace.csv","w");
    if(!fd) $fatal(1,"[WCHK_SETUP] cannot open trace");
    $fdisplay(fd,"cycle,time_ns,aw_count,r_count,w_count,b_count,data_available,len_available,data_ready,wvalid,wready,wlast,blocked_cycles");
  end

  always @(posedge bus.aclk) begin
    cycle++;
    if(!bus.aresetn) begin blocked_cycles=0; previous_stall=0; end
    else begin
      // Check the prior stalled VALID on the next sampling edge, even if READY
      // has become high. Payload must also be stable on the accepting edge.
      if(previous_stall && (bus.m_wvalid_o!==1'b1 ||
          {bus.m_wdata_o,bus.m_wstrb_o,bus.m_wlast_o} !== previous_payload))
        $fatal(1,"[WVALID_HOLD_FAIL] VALID/payload changed before handshake");
      previous_stall=(bus.m_wvalid_o===1'b1 && bus.m_wready_i===1'b0);
      previous_payload={bus.m_wdata_o,bus.m_wstrb_o,bus.m_wlast_o};
      if(bus.m_awvalid_o && bus.m_awready_i) aw_count++;
      if(bus.m_rvalid_i && bus.m_rready_o) r_count++;
      if(bus.m_wvalid_o && bus.m_wready_i) w_count++;
      if(bus.m_bvalid_i && bus.m_bready_o) b_count++;
      if(data_available===1'b1 && len_available===1'b1 && bus.m_wready_i===1'b0)
        offered_low_ready_cycles++;
      if(previous_stall) valid_low_ready_cycles++;
      // Precondition avoids mistaking missing data or missing descriptor for a
      // READY-dependence failure. A global TB timeout remains a different error.
      if(data_available===1'b1 && len_available===1'b1 &&
         bus.m_wready_i===1'b0 && bus.m_wvalid_o===1'b0) blocked_cycles++;
      else blocked_cycles=0;
      $fdisplay(fd,"%0d,%0.3f,%0d,%0d,%0d,%0d,%b,%b,%b,%b,%b,%b,%0d",
        cycle,$realtime,aw_count,r_count,w_count,b_count,data_available,len_available,
        data_ready,bus.m_wvalid_o,bus.m_wready_i,bus.m_wlast_o,blocked_cycles);
      if(blocked_cycles==1)
        $display("[WVALID_PENDING] t_ns=%0.3f data_vld=%b len_vld=%b WVALID=%b WREADY=%b W=%0d",
          $realtime,data_available,len_available,bus.m_wvalid_o,bus.m_wready_i,w_count);
      if(blocked_cycles>=limit_cycles) begin
        $fflush(fd);
        $display("[WVALID_EVIDENCE] scenario=%s t_ns=%0.3f cycles=%0d AW=%0d R=%0d W=%0d B=%0d data_vld=%b len_vld=%b data_rdy=%b WVALID=%b WREADY=%b",
          bus.scenario,$realtime,blocked_cycles,aw_count,r_count,w_count,b_count,
          data_available,len_available,data_ready,bus.m_wvalid_o,bus.m_wready_i);
        $fatal(1,"[WVALID_READY_DEPENDENCY] ready data and burst information remained pending while Slave waited for WVALID");
      end
    end
  end
  final begin
    $display("[WCHK_SUMMARY] AW=%0d R=%0d W=%0d B=%0d offered_low_ready=%0d valid_low_ready=%0d blocked=%0d",
      aw_count,r_count,w_count,b_count,offered_low_ready_cycles,valid_low_ready_cycles,blocked_cycles);
    $fclose(fd);
  end
endmodule
