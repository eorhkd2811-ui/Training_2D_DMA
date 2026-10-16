`timescale 1ns/1ps
// Shared configuration and transaction types. Memory addresses/strides are BYTES.
// Array indexes and x_words remain complete data beats; lengths retain N-1 CSR encoding.
package tb_var;
  parameter int DUT_CLK_PERIOD=2;
  parameter int ATX_MAX_LENGTH=256;
  parameter int TIMEOUT_NS=200000;
  parameter string DEFAULT_SCENARIO="IMG_STREAM";
parameter SRC_IF_TYPE       = "AXI4"; // "AXI4" || "AXIS"
parameter DST_IF_TYPE       = "AXI4"; // "AXI4" || "AXIS"



parameter DMA_BASE_ADDR     = 32'h8000_0000;
parameter DMA_CHN_NUM       = 2;    // Number of DMA channels
parameter DMA_LENGTH_W      = 16;   // Maximum size of 1 transfer is (2^16 * 256) 
parameter DMA_DESC_DEPTH    = 4;    // The maximum number of descriptors in each channel
parameter DMA_CHN_ARB_W     = 3;    // Channel arbitration weight's width
parameter ROB_EN            = 0;    // Reorder multiple AXI outstanding transactions enable
parameter DESC_QUEUE_TYPE   = (DMA_DESC_DEPTH >= 16) ? "RAM-BASED" : "FLIPFLOP-BASED";
parameter ATX_SRC_DATA_W    = 256;
parameter ATX_DST_DATA_W    = 256;
parameter S_DATA_W          = 32;
parameter S_ADDR_W          = 32;
parameter SRC_ADDR_W        = 32;
parameter SRC_TDEST_W       = 2;
parameter DST_ADDR_W        = 32;
parameter DST_TDEST_W       = 2;
parameter MST_ID_W          = 5;
parameter ATX_LEN_W         = 8;
parameter ATX_SIZE_W        = 3;
parameter ATX_RESP_W        = 2;
parameter ATX_SRC_BYTE_AMT  = ATX_SRC_DATA_W/8;
parameter ATX_DST_BYTE_AMT  = ATX_DST_DATA_W/8;
parameter ATX_NUM_OSTD      = (DMA_CHN_NUM > 1) ? DMA_CHN_NUM : 2;  // Number of outstanding transactions in AXI bus (recmd: equal to the number of channel)
parameter ATX_INTL_DEPTH    = 16; // Interleaving depth on the AXI data channel 

// Source image 
parameter SRC_PXL_W         = 16;   // pixel format RGB565
parameter SRC_IMG_W         = 640;  // width
parameter SRC_IMG_H         = 480;  // height
parameter SRC_MEM_SIZE      = (SRC_IMG_W /(ATX_SRC_DATA_W/SRC_PXL_W)) * SRC_IMG_H;  // Image size 640x480
parameter SRC_BASE_ADDR     = 32'h0000_0000;
// Destination[0] image
parameter DST_0_IMG_W       = (SRC_IF_TYPE== "AXI4") ? 320 : SRC_IMG_W;  // width
parameter DST_0_IMG_H       = (SRC_IF_TYPE== "AXI4") ? 240 : SRC_IMG_H;  // depth
parameter DST_0_PXL_W       = 16;   // pixel format RGB565
parameter DST_0_MEM_SIZE    = (DST_0_IMG_W /(ATX_DST_DATA_W/DST_0_PXL_W)) * DST_0_IMG_H;  // Image size 320x240
parameter DST_0_BASE_ADDR   = 32'h8000_0000;
parameter DST_0_IMG_START_X = 200;
parameter DST_0_IMG_START_Y = 100;
// Image crop starts at a complete source beat (same pixel rounding as before).
parameter DST_0_IMG_SHIFT   = ((DST_0_IMG_START_X /(ATX_SRC_DATA_W/SRC_PXL_W)) + (DST_0_IMG_START_Y * (SRC_IMG_W /(ATX_SRC_DATA_W/SRC_PXL_W)))) * ATX_SRC_BYTE_AMT;
// Destination[1] image
parameter DST_1_PXL_W       = 16;   // pixel format RGB565
parameter DST_1_IMG_W       = (SRC_IF_TYPE== "AXI4") ? 320 : SRC_IMG_W;  // width
parameter DST_1_IMG_H       = (SRC_IF_TYPE== "AXI4") ? 240 : SRC_IMG_H;  // depth
parameter DST_1_MEM_SIZE    = (DST_1_IMG_W /(ATX_DST_DATA_W/DST_1_PXL_W)) * DST_1_IMG_H;  // Image size 320x240
parameter DST_1_BASE_ADDR   = 32'hC000_0000;
parameter DST_1_IMG_START_X = 100;
parameter DST_1_IMG_START_Y = 200;
parameter DST_1_IMG_SHIFT   = ((DST_1_IMG_START_X /(ATX_SRC_DATA_W/SRC_PXL_W)) + (DST_1_IMG_START_Y * (SRC_IMG_W /(ATX_SRC_DATA_W/SRC_PXL_W)))) * ATX_SRC_BYTE_AMT;




/************ AXI Transaction ************/
typedef struct {
    bit                     trans_type; // Write(1) / read(0) transaction
    bit [MST_ID_W-1:0]      axid;
    bit [DST_ADDR_W-1:0]    axaddr;
    bit [1:0]               axburst;
    bit [ATX_LEN_W-1:0]     axlen;
    bit [ATX_SIZE_W-1:0]    axsize;
} atx_ax_info;
typedef struct {
    bit [ATX_DST_DATA_W-1:0]wdata [ATX_MAX_LENGTH];
    bit [ATX_LEN_W-1:0]     wlen; // length = wlen + 1
} atx_w_info;
typedef struct {
    bit [MST_ID_W-1:0]      bid;
    bit [ATX_RESP_W-1:0]    bresp;
} atx_b_info;

typedef struct packed {
    bit [MST_ID_W-1:0] rid;
    bit [S_DATA_W-1:0] data;
    bit [ATX_RESP_W-1:0] resp;
    bit last;
} csr_r_info;
localparam int CSR_TIMEOUT_CYCLES = 2000;
localparam int IRQ_POLL_LIMIT = 128;
typedef struct {
    bit [MST_ID_W-1:0]      tid;
    bit [SRC_TDEST_W-1:0]   tdest;
    bit [ATX_SRC_DATA_W-1:0]tdata;
    bit [ATX_SRC_BYTE_AMT-1:0] tkeep;
    bit [ATX_SRC_BYTE_AMT-1:0] tstrb;
    bit                     tlast;
} atx_axis; // AXI-Stream type

/****************** DMA ******************/ 
typedef struct {
    bit                     dma_en;
} dma_info;
typedef struct {
    bit [31:0]              chn_id;
    bit                     chn_en;             // Channel Enable
    bit                     chn_2d_xfer;        // 2D mode (flag)
    bit                     chn_cyclic_xfer;    // Cyclic mode (flag)
    bit                     chn_irq_msk_com;    // Interrupt completion mask
    bit                     chn_irq_msk_qed;    // Interrupt queueing mask
    bit [DMA_CHN_ARB_W-1:0] chn_arb_rate;       // Channel arbitration rate
    bit [MST_ID_W-1:0]      atx_id;             // AXI Transaction ID
    bit [1:0]               atx_src_burst;      // AXI Transaction Burst type 
    bit [1:0]               atx_dst_burst;      // AXI Transaction Burst type 
    bit [DMA_LENGTH_W:0]    atx_wd_per_burst;   // Maximum beats per burst minus one
} channel_info;
typedef struct {
    bit [31:0]              chn_id;
    bit [SRC_ADDR_W-1:0]    src_addr;
    bit [DST_ADDR_W-1:0]    dst_addr;
    bit [DMA_LENGTH_W-1:0]  xfer_xlen;
    bit [DMA_LENGTH_W-1:0]  xfer_ylen;
    bit [DMA_LENGTH_W-1:0]  src_stride;
    bit [DMA_LENGTH_W-1:0]  dst_stride;
} descriptor_info;

localparam int CSR_BYTE_AMT = S_DATA_W / 8;
localparam int CSR_CHN_OFS  = 16;

localparam [S_ADDR_W-1:0] RW_OFS   = 32'h0000_0000;
localparam [S_ADDR_W-1:0] RW1S_OFS = 32'h0000_1000;
localparam [S_ADDR_W-1:0] RO_OFS   = 32'h0000_2000;

// RW register indexes
localparam int unsigned RW_DMA_EN           = 'h00;
localparam int unsigned RW_CHN_CTRL         = 'h01;
localparam int unsigned RW_CHN_FLAGS        = 'h02;
localparam int unsigned RW_CHN_IRQ_MASK     = 'h03;
localparam int unsigned RW_CHN_ARB_RATE     = 'h04;
localparam int unsigned RW_ATX_ID           = 'h05;
localparam int unsigned RW_ATX_SRC_BURST    = 'h06;
localparam int unsigned RW_ATX_DST_BURST    = 'h07;
localparam int unsigned RW_ATX_WD_PER_BURST = 'h08;
localparam int unsigned RW_DESC_SRC_ADDR    = 'h09;
localparam int unsigned RW_DESC_DST_ADDR    = 'h0A;
localparam int unsigned RW_DESC_XLEN        = 'h0B;
localparam int unsigned RW_DESC_YLEN        = 'h0C;
localparam int unsigned RW_DESC_SRC_STRIDE  = 'h0D;
localparam int unsigned RW_DESC_DST_STRIDE  = 'h0E;

// RW1S register indexes
localparam int unsigned RW1S_DESC_SUBMIT = 'h00;

// RO register indexes
// Same status-region address; access is RW1C, not read-only.
localparam int unsigned RW1C_CHN_IRQ_SOURCE = 'h00;
localparam int unsigned RO_XFER_ID         = 'h01;
localparam int unsigned RO_XFER_DONE       = 'h02;
localparam int unsigned RO_ACTIVE_XFER_ID  = 'h03;
localparam int unsigned RO_ACTIVE_XFER_LEN = 'h04;

// Convert the internal register index to a byte-addressed CSR address.
function automatic [S_ADDR_W-1:0] csr_addr(
    input [S_ADDR_W-1:0] region_ofs,
    input int unsigned   chn_id,
    input int unsigned   reg_idx
);
    csr_addr = DMA_BASE_ADDR
             + region_ofs
             + ((chn_id * CSR_CHN_OFS + reg_idx)
                * CSR_BYTE_AMT);
endfunction

endpackage
