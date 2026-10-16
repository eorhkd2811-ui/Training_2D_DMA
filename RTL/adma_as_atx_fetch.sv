module adma_as_atx_fetch #(
    // DMA
    parameter DMA_CHN_NUM       = 4,    // Number of DMA channels
    parameter DMA_CHN_ARB_W     = 3,    // Channel arbitration weight's width
    // Descriptor 
    parameter DMA_LENGTH_W      = 16,
    // AXI Interface
    parameter SRC_ADDR_W        = 32,
    parameter DST_ADDR_W        = 32,
    parameter MST_ID_W          = 5,
    parameter ATX_LEN_W         = 8,
    // Do not configure these
    parameter DMA_CHN_NUM_W     = $clog2(DMA_CHN_NUM),
    // Memory addresses use bytes; stream address metadata keeps its existing units.
    parameter SRC_IF_TYPE      = "AXI4",
    parameter DST_IF_TYPE      = "AXI4",
    parameter ATX_SRC_BYTE_AMT = 32,
    parameter ATX_DST_BYTE_AMT = 32
) (
    input                       clk,
    input                       rst_n,
    // Transaction information
    input   [SRC_ADDR_W-1:0]    tx_src_addr,
    input   [DST_ADDR_W-1:0]    tx_dst_addr,
    input   [DMA_LENGTH_W-1:0]  tx_len,
    input                       tx_vld,
    output                      tx_rdy,
    // AXI Transaction CSR
    input   [MST_ID_W-1:0]      atx_id,
    input   [1:0]               atx_src_burst,
    input   [1:0]               atx_dst_burst,
    input   [DMA_LENGTH_W-1:0]  atx_wd_per_burst,
    // AXI Transaction information
    output  [MST_ID_W-1:0]      arid,
    output  [SRC_ADDR_W-1:0]    araddr,
    output  [ATX_LEN_W-1:0]     arlen,
    output  [1:0]               arburst,
    output  [MST_ID_W-1:0]      awid,
    output  [DST_ADDR_W-1:0]    awaddr,
    output  [ATX_LEN_W-1:0]     awlen,
    output  [1:0]               awburst,
    output                      atx_vld,
    input                       atx_rdy,
    // AXI Transaction control
    output                      atx_start,
    output                      atx_start_last
);
    // Local paramters
    localparam TX_INFO_W    = SRC_ADDR_W + DST_ADDR_W + DMA_LENGTH_W; // source address + destination address + length
    localparam BURST_FIX    = 2'b00;
    localparam BURST_INCR   = 2'b01;
    // Decode N-1 before taking the minimum. The extra bit represents 65536
    // beats when DMA_LENGTH_W=16; 13 bits also represent a full 4KB page.
    localparam COUNT_W = ((DMA_LENGTH_W + 1) > 13) ? (DMA_LENGTH_W + 1) : 13;
    localparam AXI_MAX_BEATS = (ATX_LEN_W >= 8) ? 256 : (1 << ATX_LEN_W);
    localparam SRC_ADDR_SHIFT = (SRC_IF_TYPE == "AXI4") ? $clog2(ATX_SRC_BYTE_AMT) : 0;
    localparam DST_ADDR_SHIFT = (DST_IF_TYPE == "AXI4") ? $clog2(ATX_DST_BYTE_AMT) : 0;
    // Internal signal
    wire    [SRC_ADDR_W-1:0]    tx_src_addr_spl;
    wire    [DST_ADDR_W-1:0]    tx_dst_addr_spl;
    wire    [DMA_LENGTH_W-1:0]  tx_len_spl;
    wire                        tx_spl_vld;
    wire                        tx_spl_rdy;
    
    wire    [SRC_ADDR_W-1:0]    tx_src_addr_rem;
    wire    [DST_ADDR_W-1:0]    tx_dst_addr_rem;
    wire    [DMA_LENGTH_W-1:0]  tx_len_enc_rem; // Encoded length (length = len_enc + 1)
    wire                        tx_rem_flg;
    wire    [COUNT_W-1:0]       remaining_beats;
    wire    [COUNT_W-1:0]       configured_beats;
    wire    [11:0]              src_page_offset;
    wire    [11:0]              dst_page_offset;
    wire    [12:0]              src_page_bytes;
    wire    [12:0]              dst_page_bytes;
    wire    [COUNT_W-1:0]       src_page_beats;
    wire    [COUNT_W-1:0]       dst_page_beats;
    reg     [COUNT_W-1:0]       issued_beats;

    // Module instantiation
    splitter #(
        .DATA_W     (TX_INFO_W)
    ) tx_split (
        .clk        (clk),
        .rst_n      (rst_n),
        .bwd_data   ({tx_src_addr,      tx_dst_addr,      tx_len}),
        .bwd_vld    (tx_vld),
        .bwd_rdy    (tx_rdy),
        .rem_data   ({tx_src_addr_rem,  tx_dst_addr_rem,  tx_len_enc_rem}),
        .rem_flg    (tx_rem_flg),
        .fwd_data   ({tx_src_addr_spl,  tx_dst_addr_spl,  tx_len_spl}),
        .fwd_vld    (tx_spl_vld),
        .fwd_rdy    (tx_spl_rdy)
    );

    // Combinational logic
    // Legal memory descriptors are full-width, beat-aligned FIXED/INCR accesses
    // within the address range. Keep transaction CSRs stable while active.
    // Length fields retain their existing N-1 BEAT encoding (not bytes).
    assign remaining_beats  = COUNT_W'(tx_len_spl) + COUNT_W'(1);
    assign configured_beats = COUNT_W'(atx_wd_per_burst) + COUNT_W'(1);
    assign src_page_offset  = 12'(tx_src_addr_spl);
    assign dst_page_offset  = 12'(tx_dst_addr_spl);
    assign src_page_bytes   = 13'd4096 - {1'b0, src_page_offset};
    assign dst_page_bytes   = 13'd4096 - {1'b0, dst_page_offset};
    assign src_page_beats   = COUNT_W'(src_page_bytes) >> SRC_ADDR_SHIFT;
    assign dst_page_beats   = COUNT_W'(dst_page_bytes) >> DST_ADDR_SHIFT;

    // AR and AW describe the same number of beats. Both memory boundaries
    // constrain that number; a stream address is metadata, not a byte address.
    always @* begin
        issued_beats = remaining_beats;
        if (issued_beats > configured_beats)
            issued_beats = configured_beats;
        if (issued_beats > COUNT_W'(AXI_MAX_BEATS))
            issued_beats = COUNT_W'(AXI_MAX_BEATS);
        if (((SRC_IF_TYPE == "AXI4" && atx_src_burst == BURST_FIX) ||
             (DST_IF_TYPE == "AXI4" && atx_dst_burst == BURST_FIX)) &&
            issued_beats > COUNT_W'(16))
            issued_beats = COUNT_W'(16);
        if (SRC_IF_TYPE == "AXI4" && atx_src_burst == BURST_INCR &&
            issued_beats > src_page_beats)
            issued_beats = src_page_beats;
        if (DST_IF_TYPE == "AXI4" && atx_dst_burst == BURST_INCR &&
            issued_beats > dst_page_beats)
            issued_beats = dst_page_beats;
    end

    assign tx_rem_flg       = tx_spl_vld & (remaining_beats > issued_beats);
    assign tx_len_enc_rem   = tx_rem_flg ? DMA_LENGTH_W'(remaining_beats - issued_beats - COUNT_W'(1)) : {DMA_LENGTH_W{1'b0}};
    // Advance by the ACTUAL issued length, including a shortened boundary burst.
    // Widen to the address width before shifting. FIXED addresses never advance.
    assign tx_src_addr_rem  = tx_src_addr_spl + ((atx_src_burst == BURST_INCR) ?
                              (SRC_ADDR_W'(issued_beats) << SRC_ADDR_SHIFT) : {SRC_ADDR_W{1'b0}});
    assign tx_dst_addr_rem  = tx_dst_addr_spl + ((atx_dst_burst == BURST_INCR) ?
                              (DST_ADDR_W'(issued_beats) << DST_ADDR_SHIFT) : {DST_ADDR_W{1'b0}});
    // -- AXI Transaction generator
    assign arid             = atx_id;
    assign araddr           = tx_src_addr_spl;
    assign arlen            = ATX_LEN_W'(issued_beats - COUNT_W'(1));
    assign arburst          = atx_src_burst;
    assign awid             = atx_id;
    assign awaddr           = tx_dst_addr_spl;
    assign awlen            = arlen; // If the length of tx is greater than (word_per_burst), -> get word_per_burst. Else get remainder
    assign awburst          = atx_dst_burst;
    assign atx_vld          = tx_spl_vld;
    assign tx_spl_rdy       = atx_rdy;

    assign atx_start        = tx_spl_vld & tx_spl_rdy;
    assign atx_start_last   = ~tx_rem_flg;  // No more remaining transaction
    
endmodule
