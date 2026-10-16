`timescale 1ns/1ps
// Passive checking. Expected requests/data come only from configured descriptors.
// Current memory BFM is ordered, non-interleaved; response FIFO checks share that
// explicit scope. Independent AR/AW predictor streams do NOT assume global
// arbitration order between channels or force AR-before-AW.
module tb_sb(tb_if bus);
  import tb_var::*;
  import tb_dpi::*;
  atx_ax_info aw_queue[$],ar_queue[$];
  atx_ax_info current_aw,current_ar;
  bit active=0,read_active=0;
  int beat=0,read_beat=0,ar_count=0,aw_count=0,b_count=0,r_bursts=0;
  int checked=0,read_checked=0,quiet_cycles=0;
  int inject_data=0,inject_addr=0,inject_pred=0,timeout_ns=TIMEOUT_NS;
  bit [DMA_CHN_NUM-1:0] irq_seen='0;
  bit [MST_ID_W-1:0] pending_bid[$];

  task automatic dump_results;
    int fd;
    $writememh("env/dst_mem_0.txt",bus.dst_mem_0);
    $writememh("env/dst_mem_1.txt",bus.dst_mem_1);
    if(bus.scenario=="IMG_STREAM") begin
      fd=$fopen("env/dst_mem_0_format.txt","w");
      $fwrite(fd,"Image Size: %0d x %0d\nPixel Format: RGB565",DST_0_IMG_W,DST_0_IMG_H); $fclose(fd);
      fd=$fopen("env/dst_mem_1_format.txt","w");
      $fwrite(fd,"Image Size: %0d x %0d\nPixel Format: RGB565",DST_1_IMG_W,DST_1_IMG_H); $fclose(fd);
    end
    fd=$fopen("env/tb_result.txt","w");
    if(!fd) $fatal(1,"[SB] cannot write result file");
    $fdisplay(fd,"PASS scenario=%s checked=%0d ch0=%0d ch1=%0d errors=%0d AR=%0d AW=%0d RLAST=%0d B=%0d CSR_W=%0d CSR_R=%0d IRQ_checks=%b",bus.scenario,checked,dma_ref_checked(0),dma_ref_checked(1),dma_ref_errors(),ar_count,aw_count,r_bursts,b_count,bus.csr_completed,bus.csr_reads_completed,bus.irq_checks_done);
    $fclose(fd);
  endtask

  initial begin
    if($value$plusargs("SB_INJECT_ERROR=%d",inject_data)) begin end
    if($value$plusargs("SB_INJECT_ADDR_ERROR=%d",inject_addr)) begin end
    if($value$plusargs("PRED_INJECT_LEN_ERROR=%d",inject_pred)) begin end
    if($value$plusargs("TIMEOUT_NS=%d",timeout_ns)) begin end
    #(timeout_ns);
    dma_ref_report(); dma_pred_report();
    $fatal(1,"[SB] TIMEOUT after %0d ns remaining=%0d/%0d CSR_W=%0d/%0d CSR_R=%0d/%0d AR/RLAST=%0d/%0d AW/B=%0d/%0d irq_checked=%b data_done=%b hold_AR=%b",
      timeout_ns,dma_ref_remaining(0),dma_ref_remaining(1),bus.csr_completed,bus.csr_sent,
      bus.csr_reads_completed,bus.csr_reads_sent,ar_count,r_bursts,aw_count,b_count,
      bus.irq_checks_done,bus.data_path_done,bus.hold_dma_ar);
  end

  always @(posedge bus.aclk) if(bus.aresetn && bus.model_ready && !bus.test_done) begin : sample_outputs
    atx_ax_info info;
    bit [255:0] actual;
    int ch,observed_len;
    longint unsigned address;
    bit [MST_ID_W-1:0] expected_bid;
    bit drained,predictor_empty;
    if(bus.trap !== '0) $fatal(1,"[SB] DUT trap asserted or unknown: %b",bus.trap);
    if($isunknown(bus.irq)) $fatal(1,"[SB] unknown IRQ");
    irq_seen=irq_seen|bus.irq;
    if(bus.m_arvalid_o && bus.m_arready_i) begin
      if($isunknown({bus.m_araddr_o,bus.m_arid_o,bus.m_arlen_o,bus.m_arburst_o,bus.m_arsize_o}))
        $fatal(1,"[SB] unknown AR before DPI conversion");
      info='{default:'0};
      info.axaddr=bus.m_araddr_o; info.axid=bus.m_arid_o;
      info.axlen=bus.m_arlen_o; info.axburst=bus.m_arburst_o; info.axsize=bus.m_arsize_o;
      observed_len=int'(info.axlen);
      // Checker self-test only: corrupt the local observation, never the DUT bus.
      if(ar_count==0 && inject_pred!=0) observed_len++;
      if(!dma_pred_check(0,int'(info.axid),info.axaddr,observed_len,int'(info.axsize),int'(info.axburst)))
        $fatal(1,"[SB] AR predictor mismatch");
      ar_queue.push_back(info); ar_count++;
    end
    if(bus.m_awvalid_o && bus.m_awready_i) begin
      if($isunknown({bus.m_awaddr_o,bus.m_awid_o,bus.m_awlen_o,bus.m_awburst_o,bus.m_awsize_o}))
        $fatal(1,"[SB] unknown AW before DPI conversion");
      info='{default:'0};
      info.axaddr=bus.m_awaddr_o; info.axid=bus.m_awid_o;
      info.axlen=bus.m_awlen_o; info.axburst=bus.m_awburst_o; info.axsize=bus.m_awsize_o;
      if(!dma_pred_check(1,int'(info.axid),info.axaddr,int'(info.axlen),int'(info.axsize),int'(info.axburst)))
        $fatal(1,"[SB] AW predictor mismatch");
      aw_queue.push_back(info); aw_count++;
    end
    if(bus.m_rvalid_i && bus.m_rready_o) begin
      if(!read_active) begin
        if(ar_queue.size()==0) $fatal(1,"[SB] R accepted without AR");
        current_ar=ar_queue.pop_front(); read_active=1; read_beat=0;
      end
      if($isunknown({bus.m_rdata_i,bus.m_rid_i,bus.m_rresp_i,bus.m_rlast_i})) $fatal(1,"[SB] unknown R");
      if(bus.m_rid_i!==current_ar.axid || bus.m_rresp_i!==0 ||
         bus.m_rlast_i !== (read_beat==int'(current_ar.axlen)))
        $fatal(1,"[SB] R ID/RESP/LAST/count mismatch");
      read_checked++;
      if(read_beat==int'(current_ar.axlen)) begin read_active=0; r_bursts++; end
      else read_beat++;
    end
    if(bus.m_wvalid_o && bus.m_wready_i) begin
      if(!active) begin
        if(aw_queue.size()==0) $fatal(1,"[SB] W accepted without AW (current BFM contract)");
        current_aw=aw_queue.pop_front(); active=1; beat=0;
      end
      if($isunknown({bus.m_wdata_o,bus.m_wlast_o,bus.m_wstrb_o})) $fatal(1,"[SB] unknown W payload");
      if(bus.m_wlast_o !== (beat==int'(current_aw.axlen)) || bus.m_wstrb_o !== {ATX_DST_BYTE_AMT{1'b1}})
        $fatal(1,"[SB] WLAST/count/STRB mismatch");
      ch=dma_pred_channel(int'(current_aw.axid));
      if(ch<0) $fatal(1,"[SB] unconfigured write ID %h",current_aw.axid);
      address=64'(current_aw.axaddr)+((current_aw.axburst==2'b01)?(64'(beat) << current_aw.axsize):0);
      actual=bus.m_wdata_o;
      if(checked==0 && inject_data!=0) actual[0]=~actual[0];
      if(checked==0 && inject_addr!=0) address+=ATX_DST_BYTE_AMT;
      if(address>64'hffff_ffff || !dma_ref_check(ch,32'(address),actual)) begin
        dma_ref_report(); $fatal(1,"[SB] reference mismatch at beat %0d",checked);
      end
      checked++;
      if(beat==int'(current_aw.axlen)) begin active=0; pending_bid.push_back(current_aw.axid); end
      else beat++;
    end
    if(bus.m_bvalid_i && bus.m_bready_o) begin
      if($isunknown({bus.m_bid_i,bus.m_bresp_i})) $fatal(1,"[SB] unknown B");
      if(pending_bid.size()==0) $fatal(1,"[SB] B without completed W burst");
      expected_bid=pending_bid.pop_front();
      if(bus.m_bid_i!==expected_bid || bus.m_bresp_i!==0) $fatal(1,"[SB] invalid B response");
      b_count++;
    end
    predictor_empty=1;
    for(int c=0;c<DMA_CHN_NUM;c++)
      if(dma_pred_pending(c,0)!=0 || dma_pred_pending(c,1)!=0) predictor_empty=0;
    drained=bus.sequence_done && checked>0 && predictor_empty &&
       dma_ref_remaining(0)==0 && dma_ref_remaining(1)==0 &&
       !active && !read_active && aw_queue.size()==0 && ar_queue.size()==0 && pending_bid.size()==0 &&
       ar_count==r_bursts && aw_count==b_count && read_checked==checked;
    // Latch only when data/request/response work drained. IRQ phase depends on
    // this flag; this condition intentionally does not depend on CSR/IRQ finish.
    if(drained) bus.data_path_done=1;
    if(drained && (&bus.irq_checks_done) && (&irq_seen) && !bus.csr_busy &&
       bus.csr_completed==bus.csr_sent && bus.csr_reads_completed==bus.csr_reads_sent &&
       bus.s_seq_aw_info.num()==0 && bus.s_seq_w_info.num()==0 && bus.s_seq_ar_info.num()==0 &&
       bus.s_csr_b_response.num()==0 && bus.s_csr_r_response.num()==0 &&
       !bus.s_awvalid_i && !bus.s_wvalid_i && !bus.s_arvalid_i &&
       !bus.s_bvalid_o && !bus.s_rvalid_o && !bus.m_arvalid_o && !bus.m_awvalid_o &&
       !bus.m_rvalid_i && !bus.m_wvalid_o && !bus.m_bvalid_i) quiet_cycles++;
    else quiet_cycles=0;
    // Keep monitors active throughout CSR read/clear and a final quiet interval.
    if(quiet_cycles==16) begin
      if(dma_ref_errors()!=0 || !dma_pred_finish()) $fatal(1,"[SB] model errors/unmatched requests remain");
      bus.test_done=1; dma_ref_report(); dma_pred_report(); dump_results();
      $display("[TB_PASS] scenario=%s checked=%0d ch0=%0d ch1=%0d AR=%0d RLAST=%0d AW=%0d B=%0d CSR_W=%0d CSR_R=%0d IRQ_checks=%b",
        bus.scenario,checked,dma_ref_checked(0),dma_ref_checked(1),ar_count,r_bursts,aw_count,b_count,
        bus.csr_completed,bus.csr_reads_completed,bus.irq_checks_done);
      $finish;
    end
  end
endmodule
