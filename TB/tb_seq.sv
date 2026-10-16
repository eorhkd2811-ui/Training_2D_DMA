`timescale 1ns/1ps
// Existing IMG_STREAM/CUSTOM descriptors, with shared blocking CSR and IRQ checks.
module tb_seq(tb_if bus);
  import tb_var::*;
  import tb_dpi::*;
  int unsigned csr_tag=0;
  int inject_irq_clear=0;

  // A single sequence owns CSR transactions. Independent AW/W drivers may
  // handshake in either order; this API returns only after the matching B/R.
  task automatic csr_write(input int unsigned address, input bit [31:0] value);
    atx_ax_info a;
    atx_w_info w;
    atx_b_info b;
    bit received;
    if(bus.csr_busy || bus.s_csr_b_response.num()!=0 || bus.s_csr_r_response.num()!=0)
      $fatal(1,"[CSR] overlapping transaction or stale response");
    bus.csr_busy=1;
    a='{default:'0}; a.axaddr=address; a.axid=MST_ID_W'(csr_tag++);
    a.axsize=2; // 32-bit, single beat, full WSTRB. No address-unit change here.
    w.wlen=0; w.wdata[0]='0; w.wdata[0][31:0]=value;
    bus.csr_sent++;
    bus.s_seq_aw_info.put(a); bus.s_seq_w_info.put(w);
    received=0;
    for(int t=0;t<CSR_TIMEOUT_CYCLES;t++) begin
      @(negedge bus.aclk);
      if(bus.s_csr_b_response.try_get(b)) begin received=1; break; end
    end
    if(!received) $fatal(1,"[CSR] write timeout addr=%08h id=%0d",address,a.axid);
    if(b.bid!=a.axid || b.bresp!=0) $fatal(1,"[CSR] write ID/response mismatch addr=%08h",address);
    bus.csr_busy=0;
  endtask

  task automatic csr_read(input int unsigned address, output bit [31:0] value);
    atx_ax_info a;
    csr_r_info r;
    bit received;
    if(bus.csr_busy || bus.s_csr_b_response.num()!=0 || bus.s_csr_r_response.num()!=0)
      $fatal(1,"[CSR] overlapping transaction or stale response");
    bus.csr_busy=1;
    a='{default:'0}; a.axaddr=address; a.axid=MST_ID_W'(csr_tag++); a.axsize=2;
    bus.csr_reads_sent++;
    bus.s_seq_ar_info.put(a);
    received=0;
    for(int t=0;t<CSR_TIMEOUT_CYCLES;t++) begin
      @(negedge bus.aclk);
      if(bus.s_csr_r_response.try_get(r)) begin received=1; break; end
    end
    if(!received) $fatal(1,"[CSR] read timeout addr=%08h id=%0d",address,a.axid);
    if(r.rid!=a.axid || r.resp!=0 || !r.last) $fatal(1,"[CSR] read ID/response/LAST mismatch addr=%08h",address);
    value=r.data;
    bus.csr_busy=0;
  endtask

  task automatic csr_expect(input int unsigned address, input bit [31:0] expected,
                            input string phase);
    bit [31:0] actual;
    csr_read(address,actual);
    // Checker self-test only; the original CSR response and DUT are untouched.
    if(inject_irq_clear!=0 && phase=="CH0 Completion clear") actual[0]=~actual[0];
    if(actual!=expected) $fatal(1,"[IRQ CHECK] %s addr=%08h expected=%08h actual=%08h",phase,address,expected,actual);
    $display("[IRQ CHECK] %s addr=%08h value=%08h",phase,address,actual);
  endtask

  task automatic poll_irq(input int ch, input bit [31:0] expected, input string phase);
    bit [31:0] actual;
    bit found;
    found=0;
    for(int tries=0;tries<IRQ_POLL_LIMIT;tries++) begin
      csr_read(csr_addr(RO_OFS,ch,RW1C_CHN_IRQ_SOURCE),actual);
      if((actual & ~expected)!=0) $fatal(1,"[IRQ CHECK] %s unexpected bits ch=%0d value=%h",phase,ch,actual);
      if(actual==expected) begin found=1; break; end
    end
    if(!found) $fatal(1,"[IRQ CHECK] %s poll timeout ch=%0d expected=%h actual=%h",phase,ch,expected,actual);
    $display("[IRQ CHECK] %s ch=%0d value=%08h",phase,ch,actual);
  endtask

  task automatic setup_channel(input int ch, input int burst_words);
    channel_info c;
    if(burst_words<1 || burst_words>256) $fatal(1,"[SEQ] burst_words must be 1..256");
    c.chn_id=ch; c.chn_en=1; c.chn_2d_xfer=1; c.chn_cyclic_xfer=0;
    c.chn_irq_msk_com=1; c.chn_irq_msk_qed=1; // Inspect both enabled event sources.
    c.chn_arb_rate=(ch==0)?3:5; c.atx_id=(ch==0)?2:7;
    c.atx_src_burst=2'b01; c.atx_dst_burst=2'b01;
    c.atx_wd_per_burst=burst_words-1;
    csr_write(csr_addr(RW_OFS,ch,RW_CHN_CTRL),32'(c.chn_en));
    csr_write(csr_addr(RW_OFS,ch,RW_CHN_FLAGS),32'({c.chn_cyclic_xfer,c.chn_2d_xfer}));
    csr_write(csr_addr(RW_OFS,ch,RW_CHN_IRQ_MASK),32'({c.chn_irq_msk_qed,c.chn_irq_msk_com}));
    csr_write(csr_addr(RW_OFS,ch,RW_CHN_ARB_RATE),32'(c.chn_arb_rate));
    csr_write(csr_addr(RW_OFS,ch,RW_ATX_ID),32'(c.atx_id));
    csr_write(csr_addr(RW_OFS,ch,RW_ATX_SRC_BURST),32'(c.atx_src_burst));
    csr_write(csr_addr(RW_OFS,ch,RW_ATX_DST_BURST),32'(c.atx_dst_burst));
    csr_write(csr_addr(RW_OFS,ch,RW_ATX_WD_PER_BURST),32'(c.atx_wd_per_burst));
    csr_expect(csr_addr(RW_OFS,ch,RW_CHN_FLAGS),1,"2D enabled / cyclic disabled");
    csr_expect(csr_addr(RW_OFS,ch,RW_CHN_IRQ_MASK),3,"both IRQ masks enabled");
    if(!dma_pred_config(ch,int'(c.atx_id),int'(c.atx_wd_per_burst)+1,
                        int'(c.atx_src_burst),int'(c.atx_dst_burst),ATX_SRC_BYTE_AMT))
      $fatal(1,"[SEQ] predictor channel setup failed");
  endtask

  task automatic submit_transfer(input int ch, input int unsigned src,
      input int unsigned dst, input int x_words, input int y_rows,
      input int src_stride, input int dst_stride);
    longint unsigned src_end,dst_end,dst_base,dst_bytes;
    if(ch<0 || ch>=DMA_CHN_NUM || x_words<1 || x_words>65536 || y_rows<1 || y_rows>65536 ||
       src_stride<0 || src_stride>65535 || dst_stride<0 || dst_stride>65535)
      $fatal(1,"[SEQ] descriptor exceeds channel/16-bit field ranges");
    if((src % ATX_SRC_BYTE_AMT)!=0 || (dst % ATX_DST_BYTE_AMT)!=0 ||
       (src_stride % ATX_SRC_BYTE_AMT)!=0 || (dst_stride % ATX_DST_BYTE_AMT)!=0)
      $fatal(1,"[SEQ] unaligned byte address/stride");
    // Exclusive byte ends, computed before any narrowing. Strides may overlap rows.
    src_end=64'(src)+64'(y_rows-1)*src_stride+64'(x_words)*ATX_SRC_BYTE_AMT;
    dst_end=64'(dst)+64'(y_rows-1)*dst_stride+64'(x_words)*ATX_DST_BYTE_AMT;
    dst_base=(dst[31:30]==2'b10)?64'(DST_0_BASE_ADDR):64'(DST_1_BASE_ADDR);
    dst_bytes=(dst[31:30]==2'b10)?64'(DST_0_MEM_SIZE)*ATX_DST_BYTE_AMT:64'(DST_1_MEM_SIZE)*ATX_DST_BYTE_AMT;
    if(src<SRC_BASE_ADDR || src_end>64'(SRC_BASE_ADDR)+64'(SRC_MEM_SIZE)*ATX_SRC_BYTE_AMT ||
       dst<dst_base || dst_end>dst_base+dst_bytes || src_end>64'h1_0000_0000 || dst_end>64'h1_0000_0000)
      $fatal(1,"[SEQ] descriptor outside modeled memory/32-bit address space");
    // Config is the only source of expectations. Actual DUT AR does not seed data.
    if(!dma_ref_expect(ch,src,dst,x_words,y_rows,src_stride,dst_stride,1,1) ||
       !dma_pred_expect(ch,src,dst,x_words,y_rows,src_stride,dst_stride))
      $fatal(1,"[SEQ] descriptor expectation registration failed");
    csr_write(csr_addr(RW_OFS,ch,RW_DESC_SRC_ADDR),src);
    csr_write(csr_addr(RW_OFS,ch,RW_DESC_DST_ADDR),dst);
    csr_write(csr_addr(RW_OFS,ch,RW_DESC_XLEN),32'(x_words-1));
    csr_write(csr_addr(RW_OFS,ch,RW_DESC_YLEN),32'(y_rows-1));
    csr_write(csr_addr(RW_OFS,ch,RW_DESC_SRC_STRIDE),32'(src_stride));
    csr_write(csr_addr(RW_OFS,ch,RW_DESC_DST_STRIDE),32'(dst_stride));
    $display("[SEQ] ch=%0d src_byte=%h dst_byte=%h beats/row=%0d rows=%0d byte_strides=%0d/%0d",
      ch,src,dst,x_words,y_rows,src_stride,dst_stride);
    csr_write(csr_addr(RW1S_OFS,ch,RW1S_DESC_SUBMIT),1);
  endtask

  task automatic queued_phase;
    // Only the first existing descriptor per channel is queued under this hold.
    // No Read can finish, hence Completion cannot mask a queued-only observation.
    foreach(bus.irq_checks_done[ch]) begin
      poll_irq(ch,2,"queued only, before data release");
      csr_expect(csr_addr(RO_OFS,ch,RW1C_CHN_IRQ_SOURCE),2,"queued read is non-destructive");
    end
    @(negedge bus.aclk); bus.hold_dma_ar=0;
    $display("[IRQ CHECK] initial Memory AR hold released");
  endtask

  task automatic image_stream_sequence;
    submit_transfer(0,SRC_BASE_ADDR+DST_0_IMG_SHIFT,DST_0_BASE_ADDR,
      DST_0_IMG_W/16,DST_0_IMG_H,(SRC_IMG_W/16)*ATX_SRC_BYTE_AMT,(DST_0_IMG_W/16)*ATX_DST_BYTE_AMT);
    submit_transfer(1,SRC_BASE_ADDR+DST_1_IMG_SHIFT,DST_1_BASE_ADDR,
      DST_1_IMG_W/16,DST_1_IMG_H,(SRC_IMG_W/16)*ATX_SRC_BYTE_AMT,(DST_1_IMG_W/16)*ATX_DST_BYTE_AMT);
    queued_phase();
  endtask

  task automatic custom_sequence;
    // Preserve all three original descriptors and their CH0 -> CH1 -> CH0 order.
    submit_transfer(0,SRC_BASE_ADDR+32*ATX_SRC_BYTE_AMT,DST_0_BASE_ADDR,9,4,32*ATX_SRC_BYTE_AMT,9*ATX_DST_BYTE_AMT);
    submit_transfer(1,SRC_BASE_ADDR+1024*ATX_SRC_BYTE_AMT,DST_1_BASE_ADDR,16,5,32*ATX_SRC_BYTE_AMT,16*ATX_DST_BYTE_AMT);
    queued_phase();
    submit_transfer(0,SRC_BASE_ADDR+4096*ATX_SRC_BYTE_AMT,DST_0_BASE_ADDR+128*ATX_DST_BYTE_AMT,4,2,8*ATX_SRC_BYTE_AMT,4*ATX_DST_BYTE_AMT);
  endtask

  task automatic finish_irq_checks;
    // data_path_done excludes IRQ checking, avoiding a circular completion wait.
    wait(bus.data_path_done);
    foreach(bus.irq_checks_done[ch]) begin
      poll_irq(ch,3,"Completion plus queued after data/response drain");
      csr_expect(csr_addr(RO_OFS,ch,RW1C_CHN_IRQ_SOURCE),3,"source read is non-destructive");
      csr_write(csr_addr(RO_OFS,ch,RW1C_CHN_IRQ_SOURCE),0);
      csr_expect(csr_addr(RO_OFS,ch,RW1C_CHN_IRQ_SOURCE),3,"write zero preserves pending");
    end
    // Selective clear and channel isolation, after all transfer events settle.
    csr_write(csr_addr(RO_OFS,0,RW1C_CHN_IRQ_SOURCE),1);
    csr_expect(csr_addr(RO_OFS,0,RW1C_CHN_IRQ_SOURCE),2,"CH0 Completion clear");
    csr_expect(csr_addr(RO_OFS,1,RW1C_CHN_IRQ_SOURCE),3,"CH1 unaffected by CH0 clear");
    csr_write(csr_addr(RO_OFS,0,RW1C_CHN_IRQ_SOURCE),2);
    csr_expect(csr_addr(RO_OFS,0,RW1C_CHN_IRQ_SOURCE),0,"CH0 queued clear");
    csr_expect(csr_addr(RO_OFS,1,RW1C_CHN_IRQ_SOURCE),3,"CH1 still pending");
    csr_write(csr_addr(RO_OFS,1,RW1C_CHN_IRQ_SOURCE),2);
    csr_expect(csr_addr(RO_OFS,0,RW1C_CHN_IRQ_SOURCE),0,"CH0 unaffected by CH1 clear");
    csr_expect(csr_addr(RO_OFS,1,RW1C_CHN_IRQ_SOURCE),1,"CH1 queued clear preserves Completion");
    csr_write(csr_addr(RO_OFS,1,RW1C_CHN_IRQ_SOURCE),1);
    foreach(bus.irq_checks_done[ch]) begin
      csr_expect(csr_addr(RO_OFS,ch,RW1C_CHN_IRQ_SOURCE),0,"final pending cleared");
      bus.irq_checks_done[ch]=1;
    end
    $display("[IRQ_PASS] both channels: reset/queued/completion/non-destructive read/write-zero/selective RW1C/isolation");
  endtask

  initial begin : sequence_main
    int fd;
    if($value$plusargs("IRQ_INJECT_CLEAR_ERROR=%d",inject_irq_clear)) begin end
    if($value$plusargs("SCENARIO=%s",bus.scenario)) begin end
    if(bus.scenario=="IMAGE_STREAM") bus.scenario="IMG_STREAM";
    if(bus.scenario!="IMG_STREAM" && bus.scenario!="CUSTOM" &&
       bus.scenario!="WREADY_WAIT_VALID" && bus.scenario!="WREADY_WAIT_VALID_MID")
      $fatal(1,"[SEQ] unsupported SCENARIO=%s (IMG_STREAM/CUSTOM/WREADY_WAIT_VALID/WREADY_WAIT_VALID_MID)",bus.scenario);
    if(SRC_IF_TYPE!="AXI4" || DST_IF_TYPE!="AXI4" || DMA_CHN_NUM!=2 ||
       ATX_SRC_DATA_W!=256 || ATX_DST_DATA_W!=256 || DMA_LENGTH_W!=16 || S_DATA_W!=32 ||
       SRC_ADDR_W!=32 || DST_ADDR_W!=32 || MST_ID_W!=5)
      $fatal(1,"[SEQ] scope: 2-channel AXI4/AXI4, 256-bit data, 32-bit address/CSR, 5-bit ID");
    if(!dma_ref_reset()) $fatal(1,"[SEQ] reference reset failed");
    for(int i=0;i<SRC_MEM_SIZE;i++) begin
      bus.src_mem[i]='x;
      if(bus.scenario!="IMG_STREAM")
        for(int lane=0;lane<8;lane++) bus.src_mem[i][lane*32+:32]=32'hA5C30000 ^ (i*32'h00010001) ^ (lane*32'h01020304);
    end
    foreach(bus.dst_mem_0[i]) bus.dst_mem_0[i]='0;
    foreach(bus.dst_mem_1[i]) bus.dst_mem_1[i]='0;
    if(bus.scenario=="IMG_STREAM") begin
      fd=$fopen("env/src_mem.txt","r");
      if(!fd) $fatal(1,"[SEQ] missing env/src_mem.txt");
      $fclose(fd); $readmemh("env/src_mem.txt",bus.src_mem);
    end
    for(int i=0;i<SRC_MEM_SIZE;i++) begin
      if($isunknown(bus.src_mem[i])) $fatal(1,"[SEQ] unknown source word %0d",i);
      if(!dma_ref_seed(SRC_BASE_ADDR+i*ATX_SRC_BYTE_AMT,bus.src_mem[i])) $fatal(1,"[SEQ] source seed failed at index %0d",i);
    end
    bus.model_ready=1;
    wait(bus.aresetn===1'b1); @(negedge bus.aclk);
    $display("[SEQ] Starting %s",bus.scenario);
    foreach(bus.irq_checks_done[ch]) csr_expect(csr_addr(RO_OFS,ch,RW1C_CHN_IRQ_SOURCE),0,"reset source");
    csr_write(csr_addr(RW_OFS,0,RW_DMA_EN),1);
    setup_channel(0,6); setup_channel(1,8);
    if(bus.scenario=="IMG_STREAM") image_stream_sequence(); else custom_sequence();
    bus.sequence_done=1;
    finish_irq_checks();
  end
endmodule
