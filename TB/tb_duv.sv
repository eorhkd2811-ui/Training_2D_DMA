`timescale 1ns/1ps
module tb_duv(tb_if bus);
  import tb_var::*;
    axi_dma #(
        .DMA_BASE_ADDR  (DMA_BASE_ADDR),
        .DMA_CHN_NUM    (DMA_CHN_NUM),
        .DMA_LENGTH_W   (DMA_LENGTH_W),
        .DMA_DESC_DEPTH (DMA_DESC_DEPTH),
        .DMA_CHN_ARB_W  (DMA_CHN_ARB_W),
        .ROB_EN         (ROB_EN),
        .DESC_QUEUE_TYPE(DESC_QUEUE_TYPE),
        .SRC_IF_TYPE    (SRC_IF_TYPE),
        .DST_IF_TYPE    (DST_IF_TYPE),
        .ATX_SRC_DATA_W (ATX_SRC_DATA_W),
        .ATX_DST_DATA_W (ATX_DST_DATA_W),
        .S_DATA_W       (S_DATA_W),
        .S_ADDR_W       (S_ADDR_W),
        .SRC_ADDR_W     (SRC_ADDR_W),
        .SRC_TDEST_W    (SRC_TDEST_W),
        .DST_ADDR_W     (DST_ADDR_W),
        .DST_TDEST_W    (DST_TDEST_W),
        .MST_ID_W       (MST_ID_W),
        .ATX_LEN_W      (ATX_LEN_W),
        .ATX_SIZE_W     (ATX_SIZE_W),
        .ATX_RESP_W     (ATX_RESP_W),
        .ATX_SRC_BYTE_AMT(ATX_SRC_BYTE_AMT),
        .ATX_DST_BYTE_AMT(ATX_DST_BYTE_AMT),
        .ATX_NUM_OSTD   (ATX_NUM_OSTD),
        .ATX_INTL_DEPTH (ATX_INTL_DEPTH)
    ) dut (

    // Clock / Reset
    .aclk                 (bus.aclk),
    .aresetn              (bus.aresetn),

    // ========================================================
    // AXI4 Slave Interface
    // ========================================================

    // AW Channel
    .s_awid_i             (bus.s_awid_i),
    .s_awaddr_i           (bus.s_awaddr_i),
    .s_awburst_i          (bus.s_awburst_i),
    .s_awlen_i            (bus.s_awlen_i),
    .s_awsize_i           (bus.s_awsize_i),
    .s_awvalid_i          (bus.s_awvalid_i),
    .s_awready_o          (bus.s_awready_o),

    // W Channel
    .s_wdata_i            (bus.s_wdata_i),
    .s_wstrb_i            (bus.s_wstrb_i),
    .s_wlast_i            (bus.s_wlast_i),
    .s_wvalid_i           (bus.s_wvalid_i),
    .s_wready_o           (bus.s_wready_o),

    // B Channel
    .s_bid_o              (bus.s_bid_o),
    .s_bresp_o            (bus.s_bresp_o),
    .s_bvalid_o           (bus.s_bvalid_o),
    .s_bready_i           (bus.s_bready_i),

    // AR Channel
    .s_arid_i             (bus.s_arid_i),
    .s_araddr_i           (bus.s_araddr_i),
    .s_arburst_i          (bus.s_arburst_i),
    .s_arlen_i            (bus.s_arlen_i),
    .s_arsize_i           (bus.s_arsize_i),
    .s_arvalid_i          (bus.s_arvalid_i),
    .s_arready_o          (bus.s_arready_o),

    // R Channel
    .s_rid_o              (bus.s_rid_o),
    .s_rdata_o            (bus.s_rdata_o),
    .s_rresp_o            (bus.s_rresp_o),
    .s_rlast_o            (bus.s_rlast_o),
    .s_rvalid_o           (bus.s_rvalid_o),
    .s_rready_i           (bus.s_rready_i),

    // ========================================================
    // Source Interface - AXI4
    // ========================================================

    // AR Channel
    .m_arid_o             (bus.m_arid_o),
    .m_araddr_o           (bus.m_araddr_o),
    .m_arlen_o            (bus.m_arlen_o),
    .m_arsize_o           (bus.m_arsize_o),
    .m_arburst_o          (bus.m_arburst_o),
    .m_arvalid_o          (bus.m_arvalid_o),
    .m_arready_i          (bus.m_arready_i),

    // R Channel
    .m_rid_i              (bus.m_rid_i),
    .m_rdata_i            (bus.m_rdata_i),
    .m_rresp_i            (bus.m_rresp_i),
    .m_rlast_i            (bus.m_rlast_i),
    .m_rvalid_i           (bus.m_rvalid_i),
    .m_rready_o           (bus.m_rready_o),

    // ========================================================
    // Source Interface - AXI Stream
    // ========================================================

    .s_tid_i              (bus.s_tid_i),
    .s_tdest_i            (bus.s_tdest_i),
    .s_tdata_i            (bus.s_tdata_i),
    .s_tkeep_i            (bus.s_tkeep_i),
    .s_tstrb_i            (bus.s_tstrb_i),
    .s_tlast_i            (bus.s_tlast_i),
    .s_tvalid_i           (bus.s_tvalid_i),
    .s_tready_o           (bus.s_tready_o),

    // ========================================================
    // Destination Interface - AXI4
    // ========================================================

    // AW Channel
    .m_awid_o             (bus.m_awid_o),
    .m_awaddr_o           (bus.m_awaddr_o),
    .m_awlen_o            (bus.m_awlen_o),
    .m_awsize_o           (bus.m_awsize_o),
    .m_awburst_o          (bus.m_awburst_o),
    .m_awvalid_o          (bus.m_awvalid_o),
    .m_awready_i          (bus.m_awready_i),

    // W Channel
    .m_wdata_o            (bus.m_wdata_o),
    .m_wstrb_o            (bus.m_wstrb_o),
    .m_wlast_o            (bus.m_wlast_o),
    .m_wvalid_o           (bus.m_wvalid_o),
    .m_wready_i           (bus.m_wready_i),

    // B Channel
    .m_bid_i              (bus.m_bid_i),
    .m_bresp_i            (bus.m_bresp_i),
    .m_bvalid_i           (bus.m_bvalid_i),
    .m_bready_o           (bus.m_bready_o),

    // ========================================================
    // Destination Interface - AXI Stream
    // ========================================================

    .m_tid_o              (bus.m_tid_o),
    .m_tdest_o            (bus.m_tdest_o),
    .m_tdata_o            (bus.m_tdata_o),
    .m_tkeep_o            (bus.m_tkeep_o),
    .m_tstrb_o            (bus.m_tstrb_o),
    .m_tlast_o            (bus.m_tlast_o),
    .m_tvalid_o           (bus.m_tvalid_o),
    .m_tready_i           (bus.m_tready_i),

    // ========================================================
    // Interrupt
    // ========================================================

    .irq                  (bus.irq),
    .trap                 (bus.trap)
    );

endmodule
