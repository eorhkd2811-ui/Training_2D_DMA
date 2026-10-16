`timescale 1ns/1ps
// Shared verification interface; each DUT input has exactly one driver.
interface tb_if;
  import tb_var::*;
    logic                           aclk;
    logic                           aresetn;

    // AXI4 Slave Interface            
    // -- AW channel         
    logic   [MST_ID_W-1:0]          s_awid_i;
    logic   [S_ADDR_W-1:0]          s_awaddr_i;
    logic   [1:0]                   s_awburst_i;
    logic   [ATX_LEN_W-1:0]         s_awlen_i;
    logic   [ATX_SIZE_W-1:0]        s_awsize_i;
    logic                           s_awvalid_i;
    logic                           s_awready_o;
    // -- W channel          
    logic   [S_DATA_W-1:0]          s_wdata_i;
    logic   [S_DATA_W/8-1:0]        s_wstrb_i;
    logic                           s_wlast_i;
    logic                           s_wvalid_i;
    logic                           s_wready_o;
    // -- B channel          
    logic   [MST_ID_W-1:0]          s_bid_o;
    logic   [ATX_RESP_W-1:0]        s_bresp_o;
    logic                           s_bvalid_o;
    logic                           s_bready_i;
    // -- AR channel         
    logic   [MST_ID_W-1:0]          s_arid_i;
    logic   [S_ADDR_W-1:0]          s_araddr_i;
    logic   [1:0]                   s_arburst_i;
    logic   [ATX_LEN_W-1:0]         s_arlen_i;
    logic   [ATX_SIZE_W-1:0]        s_arsize_i;
    logic                           s_arvalid_i;
    logic                           s_arready_o;
    // -- R channel          
    logic   [MST_ID_W-1:0]          s_rid_o;
    logic   [S_DATA_W-1:0]          s_rdata_o;
    logic   [ATX_RESP_W-1:0]        s_rresp_o;
    logic                           s_rlast_o;
    logic                           s_rvalid_o;
    logic                           s_rready_i;
    
    // AXI4 Master Read (source) port
    // -- AR channel         
    logic   [MST_ID_W-1:0]          m_arid_o;
    logic   [SRC_ADDR_W-1:0]        m_araddr_o;
    logic   [ATX_LEN_W-1:0]         m_arlen_o;
    logic   [ATX_SIZE_W-1:0]        m_arsize_o;
    logic   [1:0]                   m_arburst_o;
    logic                           m_arvalid_o;
    logic                           m_arready_i;
    // -- -- R channel          
    logic   [MST_ID_W-1:0]          m_rid_i;
    logic   [ATX_SRC_DATA_W-1:0]    m_rdata_i;
    logic   [ATX_RESP_W-1:0]        m_rresp_i;
    logic                           m_rlast_i;
    logic                           m_rvalid_i;
    logic                           m_rready_o;
    // -- AXI-Stream
    logic   [MST_ID_W-1:0]          s_tid_i;    
    logic   [SRC_TDEST_W-1:0]       s_tdest_i;  // Not-use
    logic   [ATX_SRC_DATA_W-1:0]    s_tdata_i;
    logic   [ATX_SRC_BYTE_AMT-1:0]  s_tkeep_i;
    logic   [ATX_SRC_BYTE_AMT-1:0]  s_tstrb_i;
    logic                           s_tlast_i;
    logic                           s_tvalid_i;
    logic                           s_tready_o;

    // Destination Interface
    // -- AXI4
    // -- -- AW channel         
    logic   [MST_ID_W-1:0]          m_awid_o;
    logic   [DST_ADDR_W-1:0]        m_awaddr_o;
    logic   [ATX_LEN_W-1:0]         m_awlen_o;
    logic   [ATX_SIZE_W-1:0]        m_awsize_o;
    logic   [1:0]                   m_awburst_o;
    logic                           m_awvalid_o;
    logic                           m_awready_i;
    // -- -- W channel          
    logic   [ATX_DST_DATA_W-1:0]    m_wdata_o;
    logic   [ATX_DST_DATA_W/8-1:0]  m_wstrb_o;
    logic                           m_wlast_o;
    logic                           m_wvalid_o;
    logic                           m_wready_i;
    // -- -- B channel
    logic   [MST_ID_W-1:0]          m_bid_i;
    logic   [ATX_RESP_W-1:0]        m_bresp_i;
    logic                           m_bvalid_i;
    logic                           m_bready_o;
    // -- AXI-Stream
    logic   [MST_ID_W-1:0]          m_tid_o;    
    logic   [DST_TDEST_W-1:0]       m_tdest_o;
    logic   [ATX_DST_DATA_W-1:0]    m_tdata_o;
    logic   [ATX_DST_BYTE_AMT-1:0]  m_tkeep_o;
    logic   [ATX_DST_BYTE_AMT-1:0]  m_tstrb_o;
    logic                           m_tlast_o;
    logic                           m_tvalid_o;
    logic                           m_tready_i;

    // Interrupt
    logic   [DMA_CHN_NUM-1:0]       irq;
    logic   [DMA_CHN_NUM-1:0]       trap;

    // Source Memory
    logic [ATX_SRC_DATA_W-1:0]      src_mem     [0:SRC_MEM_SIZE-1];
    // Destination Memory 0
    logic [ATX_DST_DATA_W-1:0]      dst_mem_0   [0:DST_0_MEM_SIZE-1];
    // Destination Memory 1
    logic [ATX_DST_DATA_W-1:0]      dst_mem_1   [0:DST_1_MEM_SIZE-1];

    // Sequence queue
    mailbox #(atx_ax_info)  s_seq_aw_info = new();
    mailbox #(atx_w_info)   s_seq_w_info = new();
    mailbox #(atx_ax_info)  s_seq_ar_info = new();
    mailbox #(atx_b_info)   s_csr_b_response = new();
    mailbox #(csr_r_info)   s_csr_r_response = new();

    // Driver queue
    mailbox #(atx_ax_info)  m_drv_aw_info = new();
    mailbox #(atx_b_info)   m_drv_b_info = new();
    mailbox #(atx_ax_info)  m_drv_ar_info = new();



  bit model_ready=0;
  bit sequence_done=0;
  bit test_done=0;
  // Sequence owns hold/IRQ flags; scoreboard owns data_path_done.
  bit hold_dma_ar=1;
  bit data_path_done=0;
  bit [DMA_CHN_NUM-1:0] irq_checks_done='0;
  bit csr_busy=0;
  string scenario=DEFAULT_SCENARIO;
  int csr_sent=0;
  int csr_completed=0;
  int csr_reads_sent=0;
  int csr_reads_completed=0;
endinterface
