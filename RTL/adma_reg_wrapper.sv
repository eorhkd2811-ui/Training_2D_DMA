module adma_reg_wrapper
#(
    // DMA
    parameter DMA_BASE_ADDR     = 32'h8000_0000,
    parameter DMA_CHN_NUM       = 4,
    parameter DMA_LENGTH_W      = 16,
    parameter DMA_DESC_DEPTH    = 4,
    parameter DMA_CHN_ARB_W     = 3,

    // AXI4 Slave
    parameter S_DATA_W          = 32,
    parameter S_ADDR_W          = 32,

    // AXI4 Bus
    parameter SRC_ADDR_W        = 32,
    parameter DST_ADDR_W        = 32,
    parameter MST_ID_W          = 5,
    parameter ATX_LEN_W         = 8,
    parameter ATX_SIZE_W        = 3,
    parameter ATX_RESP_W        = 2,

    // Do not configure
    parameter DMA_XFER_ID_W     = $clog2(DMA_DESC_DEPTH)
) (
    input                           aclk,
    input                           aresetn,

    // ============================================================
    // Standard byte-addressed AXI4 Slave Interface
    // ============================================================

    // AW channel
    input  [MST_ID_W-1:0]           s_awid_i,
    input  [S_ADDR_W-1:0]           s_awaddr_i,
    input  [1:0]                    s_awburst_i,
    input  [ATX_LEN_W-1:0]          s_awlen_i,
    input  [ATX_SIZE_W-1:0]         s_awsize_i,
    input                           s_awvalid_i,
    output                          s_awready_o,

    // W channel
    input  [S_DATA_W-1:0]           s_wdata_i,
    input  [S_DATA_W/8-1:0]         s_wstrb_i,
    input                           s_wlast_i,
    input                           s_wvalid_i,
    output                          s_wready_o,

    // B channel
    output [MST_ID_W-1:0]           s_bid_o,
    output [ATX_RESP_W-1:0]         s_bresp_o,
    output                          s_bvalid_o,
    input                           s_bready_i,

    // AR channel
    input  [MST_ID_W-1:0]           s_arid_i,
    input  [S_ADDR_W-1:0]           s_araddr_i,
    input  [1:0]                    s_arburst_i,
    input  [ATX_LEN_W-1:0]          s_arlen_i,
    input  [ATX_SIZE_W-1:0]         s_arsize_i,
    input                           s_arvalid_i,
    output                          s_arready_o,

    // R channel
    output [MST_ID_W-1:0]           s_rid_o,
    output [S_DATA_W-1:0]           s_rdata_o,
    output [ATX_RESP_W-1:0]         s_rresp_o,
    output                          s_rlast_o,
    output                          s_rvalid_o,
    input                           s_rready_i,

    // ============================================================
    // DMA CSRs
    // ============================================================

    output                          dma_en,

    // Channel CSR
    output                          chn_ctrl_en         [0:DMA_CHN_NUM-1],
    output                          chn_xfer_2d         [0:DMA_CHN_NUM-1],
    output                          chn_xfer_cyclic     [0:DMA_CHN_NUM-1],
    output                          chn_irq_msk_irq_com [0:DMA_CHN_NUM-1],
    output                          chn_irq_msk_irq_qed [0:DMA_CHN_NUM-1],

    input                           chn_irq_src_irq_com [0:DMA_CHN_NUM-1],
    input                           chn_irq_src_irq_qed [0:DMA_CHN_NUM-1],

    output [DMA_CHN_ARB_W-1:0]      chn_arb_rate        [0:DMA_CHN_NUM-1],

    // AXI4 Transaction CSR
    output [MST_ID_W-1:0]           atx_id              [0:DMA_CHN_NUM-1],
    output [1:0]                    atx_src_burst       [0:DMA_CHN_NUM-1],
    output [1:0]                    atx_dst_burst       [0:DMA_CHN_NUM-1],
    output [DMA_LENGTH_W-1:0]       atx_wd_per_burst    [0:DMA_CHN_NUM-1],

    // Descriptor Queue
    output                          desc_wr_vld_o       [0:DMA_CHN_NUM-1],
    input                           desc_wr_rdy_i       [0:DMA_CHN_NUM-1],

    output [SRC_ADDR_W-1:0]         desc_src_addr_o     [0:DMA_CHN_NUM-1],
    output [DST_ADDR_W-1:0]         desc_dst_addr_o     [0:DMA_CHN_NUM-1],
    output [DMA_LENGTH_W-1:0]       desc_xfer_xlen_o    [0:DMA_CHN_NUM-1],
    output [DMA_LENGTH_W-1:0]       desc_xfer_ylen_o    [0:DMA_CHN_NUM-1],
    output [DMA_LENGTH_W-1:0]       desc_src_strd_o     [0:DMA_CHN_NUM-1],
    output [DMA_LENGTH_W-1:0]       desc_dst_strd_o     [0:DMA_CHN_NUM-1],

    // DMA Transfer CSR
    input  [DMA_XFER_ID_W-1:0]      xfer_id             [0:DMA_CHN_NUM-1],
    input  [DMA_DESC_DEPTH-1:0]     xfer_done           [0:DMA_CHN_NUM-1],
    input  [DMA_XFER_ID_W-1:0]      active_xfer_id      [0:DMA_CHN_NUM-1],
    input  [DMA_LENGTH_W-1:0]       active_xfer_len     [0:DMA_CHN_NUM-1]
);

    // ============================================================
    // Local parameters
    // ============================================================

    localparam BYTE_AMT      = S_DATA_W / 8;
    localparam ADDR_SHIFT    = $clog2(BYTE_AMT);
    localparam CHN_STRIDE    = 16 * BYTE_AMT;

    localparam RW_REG_ADDR   = DMA_BASE_ADDR + 32'h0000_0000;
    localparam RW1S_REG_ADDR = DMA_BASE_ADDR + 32'h0000_1000;
    localparam RO_REG_ADDR   = DMA_BASE_ADDR + 32'h0000_2000;

    localparam [ATX_SIZE_W-1:0] ACCESS_SIZE =
        $clog2(BYTE_AMT);

    localparam [ATX_RESP_W-1:0] RESP_SLVERR =
        2'b10;
    localparam [ATX_RESP_W-1:0] RESP_OKAY =
        2'b00;

    // ============================================================
    // Internal adma_reg_map AXI signals
    // ============================================================

    wire [MST_ID_W-1:0]           w_awid;
    wire [S_ADDR_W-1:0]           w_awaddr;
    wire [1:0]                    w_awburst;
    wire [ATX_LEN_W-1:0]          w_awlen;
    wire                          w_awvalid;
    wire                          w_awready;

    wire [S_DATA_W-1:0]           w_wdata;
    wire                          w_wlast;
    wire                          w_wvalid;
    wire                          w_wready;

    wire [MST_ID_W-1:0]           w_bid;
    wire [ATX_RESP_W-1:0]         w_bresp;
    wire                          w_bvalid;
    wire                          w_bready;

    wire [MST_ID_W-1:0]           w_arid;
    wire [S_ADDR_W-1:0]           w_araddr;
    wire [1:0]                    w_arburst;
    wire [ATX_LEN_W-1:0]          w_arlen;
    wire                          w_arvalid;
    wire                          w_arready;

    wire [MST_ID_W-1:0]           w_rid;
    wire [S_DATA_W-1:0]           w_rdata;
    wire [ATX_RESP_W-1:0]         w_rresp;
    wire                          w_rlast;
    wire                          w_rvalid;
    wire                          w_rready;

    // ============================================================
    // Byte address to register-index address conversion
    // ============================================================

    function automatic [S_ADDR_W-1:0] translate_addr;
        input [S_ADDR_W-1:0] addr;

        begin
            // RW region
            if ((addr >= RW_REG_ADDR) &&
                (addr <  RW_REG_ADDR +
                         DMA_CHN_NUM * CHN_STRIDE)) begin

                translate_addr =
                    RW_REG_ADDR +
                    ((addr - RW_REG_ADDR) >> ADDR_SHIFT);
            end

            // RW1S region
            else if ((addr >= RW1S_REG_ADDR) &&
                     (addr <  RW1S_REG_ADDR +
                              DMA_CHN_NUM * CHN_STRIDE)) begin

                translate_addr =
                    RW1S_REG_ADDR +
                    ((addr - RW1S_REG_ADDR) >> ADDR_SHIFT);
            end

            // RO region
            else if ((addr >= RO_REG_ADDR) &&
                     (addr <  RO_REG_ADDR +
                              DMA_CHN_NUM * CHN_STRIDE)) begin

                translate_addr =
                    RO_REG_ADDR +
                    ((addr - RO_REG_ADDR) >> ADDR_SHIFT);
            end

            // Unmapped address is passed unchanged.
            // axi4_ctrl returns DECERR when no internal target matches.
            else begin
                translate_addr = addr;
            end
        end
    endfunction

    // ============================================================
    // Write transaction
    // ============================================================

    reg                           aw_stored;
    reg                           w_stored;
    reg                           aw_sent;
    reg                           w_sent;
    reg                           b_wait;
    reg                           local_bvalid;
    reg [ATX_RESP_W-1:0]          local_bresp;

    reg [MST_ID_W-1:0]            awid_reg;
    reg [S_ADDR_W-1:0]            awaddr_reg;
    reg [1:0]                     awburst_reg;
    reg [ATX_LEN_W-1:0]           awlen_reg;
    reg [ATX_SIZE_W-1:0]          awsize_reg;

    reg [S_DATA_W-1:0]            wdata_reg;
    reg [BYTE_AMT-1:0]            wstrb_reg;
    reg                           wlast_reg;

    wire                          aw_aligned;
    wire                          write_error;
    wire                          aw_hsk;
    wire                          w_hsk;
    wire                          w_aw_hsk;
    wire                          w_w_hsk;
    wire [DMA_CHN_NUM-1:0]         irq_source_wr_sel;
    wire                          irq_source_write;
    wire                          irq_clear_commit;
    wire [1:0]                    chn_irq_clear [0:DMA_CHN_NUM-1];

    // CHN_IRQ_SOURCE is RW1C at its existing status-window byte address.
    // Reads still use adma_reg_map; only writes are handled locally.
    // Commit W1C once after both AW and W are captured, independently of BREADY.
    genvar irq_chn;
    generate
        for (irq_chn = 0; irq_chn < DMA_CHN_NUM; irq_chn = irq_chn + 1) begin : IRQ_SOURCE_WR_DECODE
            localparam [S_ADDR_W-1:0] IRQ_SOURCE_ADDR =
                RO_REG_ADDR + irq_chn * CHN_STRIDE;
            assign irq_source_wr_sel[irq_chn] = (awaddr_reg == IRQ_SOURCE_ADDR);
            assign chn_irq_clear[irq_chn] =
                (irq_clear_commit && irq_source_wr_sel[irq_chn]) ? wdata_reg[1:0] : 2'b00;
        end
    endgenerate

    assign irq_source_write = |irq_source_wr_sel;
    assign irq_clear_commit = aw_stored && w_stored && irq_source_write &&
                              !write_error && !local_bvalid && !b_wait;

    assign aw_aligned =
        (awaddr_reg[ADDR_SHIFT-1:0] ==
         {ADDR_SHIFT{1'b0}});

    /*
     * Local SLVERR conditions:
     * - Unaligned address
     * - Multi-beat CSR access
     * - Access size mismatch
     * - Partial write
     * - Missing WLAST for a single-beat transfer
     */
    assign write_error =
        !aw_aligned                            ||
        (awlen_reg  != {ATX_LEN_W{1'b0}})      ||
        (awsize_reg != ACCESS_SIZE)            ||
        (wstrb_reg  != {BYTE_AMT{1'b1}})       ||
        !wlast_reg;

    /*
     * AW and W are accepted independently.
     * One write transaction can be stored at a time.
     */
    assign s_awready_o =
        !aw_stored && !b_wait && !local_bvalid;

    assign s_wready_o =
        !w_stored && !b_wait && !local_bvalid;

    assign aw_hsk =
        s_awvalid_i && s_awready_o;

    assign w_hsk =
        s_wvalid_i && s_wready_o;

    // Downstream AW
    assign w_awid    = awid_reg;
    assign w_awaddr  = translate_addr(awaddr_reg);
    assign w_awburst = awburst_reg;
    assign w_awlen   = awlen_reg;

    // Downstream W
    assign w_wdata   = wdata_reg;
    assign w_wlast   = wlast_reg;

    /*
     * AW and W are forwarded independently after both have
     * been captured and the access has passed local checks.
     */
    assign w_awvalid =
        aw_stored &&
        w_stored &&
        !write_error &&
        !irq_source_write &&
        !local_bvalid &&
        !aw_sent &&
        !b_wait;

    assign w_wvalid =
        aw_stored &&
        w_stored &&
        !write_error &&
        !irq_source_write &&
        !local_bvalid &&
        !w_sent &&
        !b_wait;

    assign w_aw_hsk =
        w_awvalid && w_awready;

    assign w_w_hsk =
        w_wvalid && w_wready;

    // B response MUX
    assign s_bid_o =
        local_bvalid ? awid_reg : w_bid;

    assign s_bresp_o =
        local_bvalid ? local_bresp : w_bresp;

    assign s_bvalid_o =
        local_bvalid ? 1'b1 :
        b_wait       ? w_bvalid :
                       1'b0;

    assign w_bready =
        b_wait &&
        !local_bvalid &&
        s_bready_i;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            aw_stored    <= 1'b0;
            w_stored     <= 1'b0;
            aw_sent      <= 1'b0;
            w_sent       <= 1'b0;
            b_wait       <= 1'b0;
            local_bvalid <= 1'b0;
            local_bresp  <= RESP_OKAY;

            awid_reg     <= {MST_ID_W{1'b0}};
            awaddr_reg   <= {S_ADDR_W{1'b0}};
            awburst_reg  <= 2'b00;
            awlen_reg    <= {ATX_LEN_W{1'b0}};
            awsize_reg   <= {ATX_SIZE_W{1'b0}};

            wdata_reg    <= {S_DATA_W{1'b0}};
            wstrb_reg    <= {BYTE_AMT{1'b0}};
            wlast_reg    <= 1'b0;
        end
        else begin
            // Independent AW handshake
            if (aw_hsk) begin
                aw_stored   <= 1'b1;
                awid_reg    <= s_awid_i;
                awaddr_reg  <= s_awaddr_i;
                awburst_reg <= s_awburst_i;
                awlen_reg   <= s_awlen_i;
                awsize_reg  <= s_awsize_i;
            end

            // Independent W handshake
            if (w_hsk) begin
                w_stored  <= 1'b1;
                wdata_reg <= s_wdata_i;
                wstrb_reg <= s_wstrb_i;
                wlast_reg <= s_wlast_i;
            end

            /*
             * Access-format errors and CHN_IRQ_SOURCE W1C are handled locally.
             * The clear pulse is separate from the held B response.
             */
            if (aw_stored &&
                w_stored &&
                (write_error || irq_source_write) &&
                !local_bvalid &&
                !b_wait) begin

                local_bvalid <= 1'b1;
                local_bresp  <= write_error ? RESP_SLVERR : RESP_OKAY;
            end

            if (w_aw_hsk) begin
                aw_sent <= 1'b1;
            end

            if (w_w_hsk) begin
                w_sent <= 1'b1;
            end

            /*
             * Enter B-response wait state after both AW and W
             * have been accepted by adma_reg_map.
             */
            if (aw_stored &&
                w_stored &&
                !write_error &&
                !irq_source_write &&
                !local_bvalid &&
                (aw_sent || w_aw_hsk) &&
                (w_sent  || w_w_hsk) &&
                !b_wait) begin

                b_wait <= 1'b1;
            end

            // Local response completed
            if (local_bvalid && s_bready_i) begin
                aw_stored    <= 1'b0;
                w_stored     <= 1'b0;
                aw_sent      <= 1'b0;
                w_sent       <= 1'b0;
                local_bvalid <= 1'b0;
            end

            // Downstream response completed
            if (b_wait &&
                w_bvalid &&
                s_bready_i) begin

                aw_stored <= 1'b0;
                w_stored  <= 1'b0;
                aw_sent   <= 1'b0;
                w_sent    <= 1'b0;
                b_wait    <= 1'b0;
            end
        end
    end

    // ============================================================
    // Read transaction
    // ============================================================

    reg                           ar_stored;
    reg                           ar_sent;
    reg                           r_wait;
    reg                           local_rvalid;

    reg [MST_ID_W-1:0]            arid_reg;
    reg [S_ADDR_W-1:0]            araddr_reg;
    reg [1:0]                     arburst_reg;
    reg [ATX_LEN_W-1:0]           arlen_reg;
    reg [ATX_SIZE_W-1:0]          arsize_reg;

    wire                          ar_aligned;
    wire                          read_error;
    wire                          ar_hsk;
    wire                          w_ar_hsk;

    assign ar_aligned =
        (araddr_reg[ADDR_SHIFT-1:0] ==
         {ADDR_SHIFT{1'b0}});

    /*
     * Local SLVERR conditions:
     * - Unaligned address
     * - Multi-beat CSR access
     * - Access size mismatch
     */
    assign read_error =
        !ar_aligned                            ||
        (arlen_reg  != {ATX_LEN_W{1'b0}})      ||
        (arsize_reg != ACCESS_SIZE);

    assign s_arready_o =
        !ar_stored && !r_wait && !local_rvalid;

    assign ar_hsk =
        s_arvalid_i && s_arready_o;

    // Downstream AR
    assign w_arid    = arid_reg;
    assign w_araddr  = translate_addr(araddr_reg);
    assign w_arburst = arburst_reg;
    assign w_arlen   = arlen_reg;

    assign w_arvalid =
        ar_stored &&
        !read_error &&
        !ar_sent &&
        !r_wait;

    assign w_ar_hsk =
        w_arvalid && w_arready;

    // R response MUX
    assign s_rid_o =
        local_rvalid ? arid_reg : w_rid;

    assign s_rdata_o =
        local_rvalid ? {S_DATA_W{1'b0}} : w_rdata;

    assign s_rresp_o =
        local_rvalid ? RESP_SLVERR : w_rresp;

    assign s_rlast_o =
        local_rvalid ? 1'b1 : w_rlast;

    assign s_rvalid_o =
        local_rvalid ? 1'b1 :
        r_wait       ? w_rvalid :
                       1'b0;

    assign w_rready =
        r_wait &&
        !local_rvalid &&
        s_rready_i;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            ar_stored    <= 1'b0;
            ar_sent      <= 1'b0;
            r_wait       <= 1'b0;
            local_rvalid <= 1'b0;

            arid_reg     <= {MST_ID_W{1'b0}};
            araddr_reg   <= {S_ADDR_W{1'b0}};
            arburst_reg  <= 2'b00;
            arlen_reg    <= {ATX_LEN_W{1'b0}};
            arsize_reg   <= {ATX_SIZE_W{1'b0}};
        end
        else begin
            // AR handshake
            if (ar_hsk) begin
                ar_stored   <= 1'b1;
                arid_reg    <= s_arid_i;
                araddr_reg  <= s_araddr_i;
                arburst_reg <= s_arburst_i;
                arlen_reg   <= s_arlen_i;
                arsize_reg  <= s_arsize_i;
            end

            /*
             * Access-format error.
             * The request is not forwarded to adma_reg_map.
             */
            if (ar_stored &&
                read_error &&
                !local_rvalid &&
                !r_wait) begin

                local_rvalid <= 1'b1;
            end

            // Downstream AR accepted
            if (w_ar_hsk) begin
                ar_sent <= 1'b1;
                r_wait  <= 1'b1;
            end

            // Local SLVERR response completed
            if (local_rvalid && s_rready_i) begin
                ar_stored    <= 1'b0;
                ar_sent      <= 1'b0;
                local_rvalid <= 1'b0;
            end

            // Downstream R response completed
            if (r_wait &&
                w_rvalid &&
                s_rready_i &&
                w_rlast) begin

                ar_stored <= 1'b0;
                ar_sent   <= 1'b0;
                r_wait    <= 1'b0;
            end
        end
    end

    // ============================================================
    // Existing adma_reg_map instance
    // ============================================================

    adma_reg_map #(
        .DMA_BASE_ADDR     (DMA_BASE_ADDR),
        .DMA_CHN_NUM       (DMA_CHN_NUM),
        .DMA_LENGTH_W      (DMA_LENGTH_W),
        .DMA_DESC_DEPTH    (DMA_DESC_DEPTH),
        .DMA_CHN_ARB_W     (DMA_CHN_ARB_W),

        .S_DATA_W          (S_DATA_W),
        .S_ADDR_W          (S_ADDR_W),

        .SRC_ADDR_W        (SRC_ADDR_W),
        .DST_ADDR_W        (DST_ADDR_W),
        .MST_ID_W          (MST_ID_W),
        .ATX_LEN_W         (ATX_LEN_W),
        .ATX_SIZE_W        (ATX_SIZE_W),
        .ATX_RESP_W        (ATX_RESP_W),

        .DMA_XFER_ID_W     (DMA_XFER_ID_W)
    ) u_adma_reg_map (
        .aclk                     (aclk),
        .aresetn                  (aresetn),

        // AW
        .s_awid_i                 (w_awid),
        .s_awaddr_i               (w_awaddr),
        .s_awburst_i              (w_awburst),
        .s_awlen_i                (w_awlen),
        .s_awvalid_i              (w_awvalid),
        .s_awready_o              (w_awready),

        // W
        .s_wdata_i                (w_wdata),
        .s_wlast_i                (w_wlast),
        .s_wvalid_i               (w_wvalid),
        .s_wready_o               (w_wready),

        // B
        .s_bid_o                  (w_bid),
        .s_bresp_o                (w_bresp),
        .s_bvalid_o               (w_bvalid),
        .s_bready_i               (w_bready),

        // AR
        .s_arid_i                 (w_arid),
        .s_araddr_i               (w_araddr),
        .s_arburst_i              (w_arburst),
        .s_arlen_i                (w_arlen),
        .s_arvalid_i              (w_arvalid),
        .s_arready_o              (w_arready),

        // R
        .s_rid_o                  (w_rid),
        .s_rdata_o                (w_rdata),
        .s_rresp_o                (w_rresp),
        .s_rlast_o                (w_rlast),
        .s_rvalid_o               (w_rvalid),
        .s_rready_i               (w_rready),

        // DMA CSR
        .dma_en                   (dma_en),

        // Channel CSR
        .chn_ctrl_en              (chn_ctrl_en),
        .chn_xfer_2d              (chn_xfer_2d),
        .chn_xfer_cyclic          (chn_xfer_cyclic),
        .chn_irq_msk_irq_com      (chn_irq_msk_irq_com),
        .chn_irq_msk_irq_qed      (chn_irq_msk_irq_qed),
        .chn_irq_src_irq_com      (chn_irq_src_irq_com),
        .chn_irq_src_irq_qed      (chn_irq_src_irq_qed),
        .chn_irq_clear            (chn_irq_clear),
        .chn_arb_rate             (chn_arb_rate),

        // AXI Transaction CSR
        .atx_id                   (atx_id),
        .atx_src_burst            (atx_src_burst),
        .atx_dst_burst            (atx_dst_burst),
        .atx_wd_per_burst         (atx_wd_per_burst),

        // Descriptor Queue
        .desc_wr_vld_o            (desc_wr_vld_o),
        .desc_wr_rdy_i            (desc_wr_rdy_i),
        .desc_src_addr_o          (desc_src_addr_o),
        .desc_dst_addr_o          (desc_dst_addr_o),
        .desc_xfer_xlen_o         (desc_xfer_xlen_o),
        .desc_xfer_ylen_o         (desc_xfer_ylen_o),
        .desc_src_strd_o          (desc_src_strd_o),
        .desc_dst_strd_o          (desc_dst_strd_o),

        // Transfer status
        .xfer_id                  (xfer_id),
        .xfer_done                (xfer_done),
        .active_xfer_id           (active_xfer_id),
        .active_xfer_len          (active_xfer_len)
    );

endmodule
