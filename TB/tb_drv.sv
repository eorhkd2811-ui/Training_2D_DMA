`timescale 1ns/1ps

// Signal-level BFM for aligned, full-width AXI BYTE addresses.
// Bus addresses are converted to local word-array indexes only at the memory model.
module tb_drv(tb_if bus);
    import tb_var::*;

    mailbox #(atx_ax_info) read_requests = new();
    mailbox #(atx_ax_info) write_requests = new();
    mailbox #(atx_b_info) write_responses = new();
    int stall_max = 0;
    int valid_hold_cycles = 2;
    string selected_scenario = "CUSTOM";
    int w_accepted = 0;

    // Deterministic independently phased delays; no global random-state coupling.
    function automatic int delay_cycles(input int unsigned ordinal,
                                         input int unsigned channel);
        if (stall_max == 0) return 0;
        return (ordinal + channel) % (stall_max + 1);
    endfunction

    function automatic int unsigned word_index(input atx_ax_info info,
          input int unsigned beat, input int unsigned base, input int byte_amt);
        logic [63:0] address;
        address={32'b0,info.axaddr};
        if(info.axburst==2'b01) address += (64'(beat) << info.axsize);
        else if(info.axburst!=2'b00)
            $fatal(1,"[DRV] unsupported burst %b",info.axburst);
        if(address>64'hffff_ffff || address<64'(base) ||
           ((address-64'(base)) % byte_amt)!=0)
            $fatal(1,"[DRV] invalid byte address=%h base=%h",address,base);
        return int'((address-64'(base))/byte_amt);
    endfunction

    task automatic check_byte_request(input atx_ax_info info, input int byte_amt);
        int beats;
        beats=int'(info.axlen)+1;
        if(info.axsize!=$clog2(byte_amt) || (info.axaddr % byte_amt)!=0)
            $fatal(1,"[DRV] unaligned/narrow access addr=%h AxSIZE=%0d bytes=%0d",
                info.axaddr,info.axsize,byte_amt);
        if(info.axburst==2'b00 && beats>16)
            $fatal(1,"[DRV] FIXED burst exceeds 16 beats");
        if(info.axburst==2'b01 && (int'(info.axaddr[11:0])+beats*byte_amt)>4096)
            $fatal(1,"[DRV] 4KB crossing addr=%h beats=%0d bytes=%0d",info.axaddr,beats,byte_amt);
        if(info.axburst!=2'b00 && info.axburst!=2'b01)
            $fatal(1,"[DRV] supported bursts are FIXED/INCR");
    endtask

    initial begin : SETTINGS
        if ($value$plusargs("STALL_MAX=%d", stall_max)) begin end
        if ($value$plusargs("SCENARIO=%s", selected_scenario)) begin end
        if ($value$plusargs("WVALID_HOLD_CYCLES=%d", valid_hold_cycles)) begin end
        if (valid_hold_cycles < 1 || valid_hold_cycles > 16)
            $fatal(1,"[DRV] WVALID_HOLD_CYCLES must be 1..16");
        if (stall_max < 0 || stall_max > 1000)
            $fatal(1, "[DRV] STALL_MAX must be 0..1000");
        if (SRC_IF_TYPE != "AXI4" || DST_IF_TYPE != "AXI4")
            $fatal(1, "[DRV] This testbench currently supports AXI4-to-AXI4 only; AXIS driver is not implemented");
        if (SRC_ADDR_W != 32 || DST_ADDR_W != 32)
            $fatal(1, "[DRV] Current memory map requires 32-bit source/destination addresses");
        $display("[DRV] Byte-addressed AXI4 memory BFM; deterministic STALL_MAX=%0d", stall_max);
    end

    // CSR responses are accepted continuously; unused streams stay inactive.
    initial begin : CONSTANT_INPUTS
        bus.s_bready_i = 1'b1;
        bus.s_rready_i = 1'b1;
        bus.s_tid_i = '0;
        bus.s_tdest_i = '0;
        bus.s_tdata_i = '0;
        bus.s_tkeep_i = '0;
        bus.s_tstrb_i = '0;
        bus.s_tlast_i = 1'b0;
        bus.s_tvalid_i = 1'b0;
        bus.m_tready_i = 1'b0;
    end

    initial begin : CSR_AW_DRIVER
        atx_ax_info info;
        bus.s_awid_i = '0;
        bus.s_awaddr_i = '0;
        bus.s_awburst_i = '0;
        bus.s_awlen_i = '0;
        bus.s_awsize_i = '0;
        bus.s_awvalid_i = 1'b0;
        wait (bus.aresetn === 1'b1);
        forever begin
            bus.s_seq_aw_info.get(info);
            @(negedge bus.aclk);
            bus.s_awid_i = info.axid;
            bus.s_awaddr_i = info.axaddr;
            bus.s_awburst_i = info.axburst;
            bus.s_awlen_i = info.axlen;
            bus.s_awsize_i = info.axsize;
            bus.s_awvalid_i = 1'b1;
            do @(posedge bus.aclk); while (bus.s_awready_o !== 1'b1);
            @(negedge bus.aclk);
            bus.s_awvalid_i = 1'b0;
        end
    end

    initial begin : CSR_W_DRIVER
        atx_w_info info;
        bus.s_wdata_i = '0;
        bus.s_wstrb_i = '0;
        bus.s_wlast_i = 1'b0;
        bus.s_wvalid_i = 1'b0;
        wait (bus.aresetn === 1'b1);
        forever begin
            bus.s_seq_w_info.get(info);
            for (int beat = 0; beat <= int'(info.wlen); beat++) begin
                @(negedge bus.aclk);
                bus.s_wdata_i = info.wdata[beat][S_DATA_W-1:0];
                bus.s_wlast_i = (beat == int'(info.wlen));
                bus.s_wstrb_i = {S_DATA_W/8{1'b1}};
                bus.s_wvalid_i = 1'b1;
                do @(posedge bus.aclk); while (bus.s_wready_o !== 1'b1);
                @(negedge bus.aclk);
                bus.s_wvalid_i = 1'b0;
                bus.s_wlast_i = 1'b0;
            end
        end
    end

    // Only this process drives CSR AR. AW/W drivers remain independent.
    initial begin : CSR_AR_DRIVER
        atx_ax_info info;
        bus.s_arid_i='0; bus.s_araddr_i='0; bus.s_arburst_i='0;
        bus.s_arlen_i='0; bus.s_arsize_i='0; bus.s_arvalid_i=0;
        wait(bus.aresetn === 1'b1);
        forever begin
            bus.s_seq_ar_info.get(info);
            @(negedge bus.aclk);
            bus.s_arid_i=info.axid; bus.s_araddr_i=info.axaddr;
            bus.s_arburst_i=info.axburst; bus.s_arlen_i=info.axlen;
            bus.s_arsize_i=info.axsize; bus.s_arvalid_i=1;
            do @(posedge bus.aclk); while(bus.s_arready_o !== 1'b1);
            @(negedge bus.aclk);
            bus.s_arvalid_i=0;
        end
    end

    // One collector per response channel. Sequence consumes each response once.
    initial begin : CSR_RESPONSE_CHECK
        atx_b_info b;
        csr_r_info r;
        bit [MST_ID_W-1:0] aw_ids[$], ar_ids[$];
        bit [MST_ID_W-1:0] expected_id;
        int w_completed;
        w_completed=0;
        forever begin
            @(posedge bus.aclk);
            // Require actual request acceptance, not merely mailbox enqueue.
            if(bus.aresetn && bus.s_awvalid_i && bus.s_awready_o) aw_ids.push_back(bus.s_awid_i);
            if(bus.aresetn && bus.s_wvalid_i && bus.s_wready_o) begin
                if(bus.s_wlast_i !== 1'b1) $fatal(1,"[CSR] expected single W beat");
                w_completed++;
            end
            if(bus.aresetn && bus.s_arvalid_i && bus.s_arready_o) ar_ids.push_back(bus.s_arid_i);
            if(bus.aresetn && bus.s_bvalid_o && bus.s_bready_i) begin
                if($isunknown({bus.s_bid_o,bus.s_bresp_o}) || bus.s_bresp_o !== 2'b00)
                    $fatal(1,"[CSR] invalid B response");
                if(bus.csr_completed >= bus.csr_sent)
                    $fatal(1,"[CSR] unexpected extra B response");
                if(aw_ids.size()==0 || w_completed==0) $fatal(1,"[CSR] B before accepted AW/W");
                expected_id=aw_ids.pop_front(); w_completed--;
                if(bus.s_bid_o !== expected_id) $fatal(1,"[CSR] B ID mismatch");
                b.bid=bus.s_bid_o; b.bresp=bus.s_bresp_o;
                bus.csr_completed++;
                bus.s_csr_b_response.put(b);
            end
            if(bus.aresetn && bus.s_rvalid_o && bus.s_rready_i) begin
                if($isunknown({bus.s_rid_o,bus.s_rdata_o,bus.s_rresp_o,bus.s_rlast_o}) ||
                   bus.s_rresp_o !== 2'b00 || bus.s_rlast_o !== 1'b1)
                    $fatal(1,"[CSR] invalid R response");
                if(bus.csr_reads_completed >= bus.csr_reads_sent)
                    $fatal(1,"[CSR] unexpected extra R response");
                if(ar_ids.size()==0) $fatal(1,"[CSR] R before accepted AR");
                expected_id=ar_ids.pop_front();
                if(bus.s_rid_o !== expected_id) $fatal(1,"[CSR] R ID mismatch");
                r.rid=bus.s_rid_o; r.data=bus.s_rdata_o;
                r.resp=bus.s_rresp_o; r.last=bus.s_rlast_o;
                bus.csr_reads_completed++;
                bus.s_csr_r_response.put(r);
            end
        end
    end

    // AW and AR have independent ready generators and capture every actual
    // rising-edge handshake once. In particular, AW never drives ARREADY.
    initial begin : MEMORY_AW_CAPTURE
        atx_ax_info info;
        int remaining = 0;
        int unsigned ordinal = 0;
        bus.m_awready_i = 1'b0;
        wait (bus.aresetn === 1'b1 && bus.model_ready);
        forever begin
            @(negedge bus.aclk);
            bus.m_awready_i = (remaining == 0);
            if (remaining > 0) remaining--;
            @(posedge bus.aclk);
            if (bus.m_awvalid_o === 1'b1 && bus.m_awready_i) begin
                if ($isunknown({bus.m_awid_o,bus.m_awaddr_o,bus.m_awlen_o,bus.m_awburst_o,bus.m_awsize_o}))
                    $fatal(1,"[DRV] unknown AW metadata");
                info.trans_type = 1'b1;
                info.axid = bus.m_awid_o;
                info.axaddr = bus.m_awaddr_o;
                info.axburst = bus.m_awburst_o;
                info.axlen = bus.m_awlen_o;
                info.axsize = bus.m_awsize_o;
                check_byte_request(info,ATX_DST_BYTE_AMT);
                if (bus.m_awsize_o !== $clog2(ATX_DST_BYTE_AMT))
                    $fatal(1, "[DRV] invalid AWSIZE=%0d expected=%0d", bus.m_awsize_o, $clog2(ATX_DST_BYTE_AMT));
                if (info.axburst != 2'b00 && info.axburst != 2'b01)
                    $fatal(1, "[DRV] Destination supports FIXED/INCR bursts only");
                if (info.axaddr[31:30] != 2'b10 && info.axaddr[31:30] != 2'b11)
                    $fatal(1, "[DRV] Destination address outside modeled regions: %08h", info.axaddr);
                write_requests.put(info);
                remaining = delay_cycles(ordinal++, 1);
            end
        end
    end

    initial begin : MEMORY_AR_CAPTURE
        atx_ax_info info;
        int remaining = 0;
        int unsigned ordinal = 0;
        bus.m_arready_i = 1'b0;
        wait (bus.aresetn === 1'b1 && bus.model_ready);
        forever begin
            @(negedge bus.aclk);
            bus.m_arready_i = (remaining == 0) && !bus.hold_dma_ar;
            if (remaining > 0) remaining--;
            @(posedge bus.aclk);
            if (bus.m_arvalid_o === 1'b1 && bus.m_arready_i) begin
                if ($isunknown({bus.m_arid_o,bus.m_araddr_o,bus.m_arlen_o,bus.m_arburst_o,bus.m_arsize_o}))
                    $fatal(1,"[DRV] unknown AR metadata");
                info.trans_type = 1'b0;
                info.axid = bus.m_arid_o;
                info.axaddr = bus.m_araddr_o;
                info.axburst = bus.m_arburst_o;
                info.axlen = bus.m_arlen_o;
                info.axsize = bus.m_arsize_o;
                check_byte_request(info,ATX_SRC_BYTE_AMT);
                if (bus.m_arsize_o !== $clog2(ATX_SRC_BYTE_AMT))
                    $fatal(1, "[DRV] invalid ARSIZE=%0d expected=%0d", bus.m_arsize_o, $clog2(ATX_SRC_BYTE_AMT));
                if (info.axburst != 2'b00 && info.axburst != 2'b01)
                    $fatal(1, "[DRV] Source supports FIXED/INCR bursts only");
                if (info.axaddr[31:30] != 2'b00)
                    $fatal(1, "[DRV] Source address outside modeled region: %08h", info.axaddr);
                read_requests.put(info);
                remaining = delay_cycles(ordinal++, 2);
            end
        end
    end

    initial begin : MEMORY_R_RESPONSE
        atx_ax_info info;
        int unsigned index;
        int unsigned ordinal = 0;
        bus.m_rid_i = '0;
        bus.m_rdata_i = '0;
        bus.m_rresp_i = '0;
        bus.m_rlast_i = 1'b0;
        bus.m_rvalid_i = 1'b0;
        wait (bus.aresetn === 1'b1 && bus.model_ready);
        forever begin
            read_requests.get(info);
            for (int beat = 0; beat <= int'(info.axlen); beat++) begin
                index = word_index(info, beat, SRC_BASE_ADDR, ATX_SRC_BYTE_AMT);
                if (index >= SRC_MEM_SIZE)
                    $fatal(1, "[DRV] Source read out of bounds address=%08h beat=%0d index=%0d", info.axaddr, beat, index);
                repeat (delay_cycles(ordinal++, 3)) @(negedge bus.aclk);
                @(negedge bus.aclk);
                bus.m_rid_i = info.axid;
                bus.m_rdata_i = bus.src_mem[index];
                bus.m_rresp_i = 2'b00;
                bus.m_rlast_i = (beat == int'(info.axlen));
                bus.m_rvalid_i = 1'b1;
                do @(posedge bus.aclk); while (bus.m_rready_o !== 1'b1);
                @(negedge bus.aclk);
                bus.m_rvalid_i = 1'b0;
                bus.m_rlast_i = 1'b0;
            end
        end
    end

    initial begin : MEMORY_W_RECEIVE
        atx_ax_info info;
        atx_b_info response;
        int unsigned index;
        int unsigned ordinal = 0;
        bus.m_wready_i = 1'b0;
        wait (bus.aresetn === 1'b1 && bus.model_ready);
        forever begin
            write_requests.get(info);
            for (int beat = 0; beat <= int'(info.axlen); beat++) begin
                index = word_index(info, beat,
                    (info.axaddr[31:30]==2'b10)?DST_0_BASE_ADDR:DST_1_BASE_ADDR,
                    ATX_DST_BYTE_AMT);
                if ((info.axaddr[31:30] == 2'b10 && index >= DST_0_MEM_SIZE) ||
                    (info.axaddr[31:30] == 2'b11 && index >= DST_1_MEM_SIZE))
                    $fatal(1, "[DRV] Destination write out of bounds address=%08h beat=%0d index=%0d", info.axaddr, beat, index);
                repeat (delay_cycles(ordinal++, 4)) @(negedge bus.aclk);
                @(negedge bus.aclk);
                // Legal Slave policy: hold WREADY low until WVALID is sampled.
                // Drive only on falling edges; no combinational READY/VALID loop.
                if (selected_scenario == "WREADY_WAIT_VALID" ||
                    (selected_scenario == "WREADY_WAIT_VALID_MID" && w_accepted > 0)) begin
                    $display("[WREADY_WAIT] t_ns=%0.3f id=%0d burst_beat=%0d accepted=%0d",
                             $realtime, info.axid, beat, w_accepted);
                    do @(posedge bus.aclk); while (bus.m_wvalid_o !== 1'b1);
                    // Exercise VALID/payload hold, then acknowledge on a later edge.
                    repeat(valid_hold_cycles) @(posedge bus.aclk);
                    @(negedge bus.aclk);
                end
                bus.m_wready_i = 1'b1;
                do @(posedge bus.aclk); while (bus.m_wvalid_o !== 1'b1);
                w_accepted++;
                if (bus.m_wlast_o !== (beat == int'(info.axlen)))
                    $fatal(1, "[DRV] WLAST mismatch id=%0d beat=%0d AWLEN=%0d WLAST=%b", info.axid, beat, info.axlen, bus.m_wlast_o);
                if (bus.m_wstrb_o !== {ATX_DST_BYTE_AMT{1'b1}})
                    $fatal(1, "[DRV] invalid WSTRB=%h expected all ones", bus.m_wstrb_o);
                if (info.axaddr[31:30] == 2'b10)
                    bus.dst_mem_0[index] = bus.m_wdata_o;
                else
                    bus.dst_mem_1[index] = bus.m_wdata_o;
                @(negedge bus.aclk);
                bus.m_wready_i = 1'b0;
            end
            response.bid = info.axid;
            response.bresp = 2'b00;
            write_responses.put(response);
        end
    end

    initial begin : MEMORY_B_RESPONSE
        atx_b_info response;
        int unsigned ordinal = 0;
        bus.m_bid_i = '0;
        bus.m_bresp_i = '0;
        bus.m_bvalid_i = 1'b0;
        wait (bus.aresetn === 1'b1 && bus.model_ready);
        forever begin
            write_responses.get(response);
            repeat (delay_cycles(ordinal++, 5)) @(negedge bus.aclk);
            @(negedge bus.aclk);
            bus.m_bid_i = response.bid;
            bus.m_bresp_i = response.bresp;
            bus.m_bvalid_i = 1'b1;
            do @(posedge bus.aclk); while (bus.m_bready_o !== 1'b1);
            @(negedge bus.aclk);
            bus.m_bvalid_i = 1'b0;
        end
    end
endmodule
