`timescale 1ns/1ps
// Focused reproduction against the unmodified Latest RTL W-channel module.
// Input data is held until accepted. No replacement DUT logic or force/release.
module tb_wvalid_unit;
  reg clk=0, rst_n=0;
  always #5 clk=~clk;
  reg [7:0] atx_awlen=0;
  reg atx_vld=0, atx_wdata_vld=0, m_wready_i=0;
  reg [255:0] atx_wdata=0;
  wire atx_rdy, atx_wdata_rdy, m_wlast_o, m_wvalid_o;
  wire [255:0] m_wdata_o;
  adma_dm_axi_w #(.ATX_LEN_W(8),.ATX_DST_DATA_W(256),.ATX_NUM_OSTD(2)) dut(.*);
  string mode="READY_FIRST";
  int beats=4, limit_cycles=32, accepted=0, wait_count=0;
  int fd;
  reg [255:0] expected_data;
  function automatic [255:0] pattern(input int n);
    for(int j=0;j<8;j++) pattern[j*32+:32]=32'h5a000000 ^ (n<<8) ^ j;
  endfunction
  initial begin
    if($value$plusargs("MODE=%s",mode)) begin end
    if($value$plusargs("BEATS=%d",beats)) begin end
    if($value$plusargs("WVALID_TIMEOUT_CYCLES=%d",limit_cycles)) begin end
    if(beats<1 || beats>256 || limit_cycles<2) $fatal(1,"[UNIT_SETUP] bad arguments");
    if(mode!="READY_FIRST" && mode!="WAIT_VALID" && mode!="WAIT_VALID_MID")
      $fatal(1,"[UNIT_SETUP] bad mode");
    if(mode=="WAIT_VALID_MID" && beats<2) $fatal(1,"[UNIT_SETUP] MID requires two beats");
    fd=$fopen("unit_trace.csv","w");
    if(!fd) $fatal(1,"[UNIT_SETUP] trace open failed");
    $fdisplay(fd,"time_ns,accepted,data_vld,len_vld,data_ready,wvalid,wready,wlast");
    if($test$plusargs("DUMP_WAVE")) begin $dumpfile("wave.vcd"); $dumpvars(0,tb_wvalid_unit); end
    repeat(4) @(negedge clk); rst_n=1;
    @(negedge clk); atx_awlen=8'(beats-1); atx_vld=1;
    do @(posedge clk); while(!atx_rdy);
    @(negedge clk); atx_vld=0;
    // Ensure metadata exists before data is made available.
    wait(dut.wdata_len_vld===1'b1);
    for(int n=0;n<beats;n++) begin
      @(negedge clk);
      atx_wdata=pattern(n); expected_data=pattern(n); atx_wdata_vld=1;
      m_wready_i=0;
      if(mode=="WAIT_VALID" || (mode=="WAIT_VALID_MID" && n>0)) begin
        wait_count=0;
        do begin
          @(posedge clk);
          if(dut.wdata_len_vld!==1 || atx_wdata_vld!==1)
            $fatal(1,"[UNIT_SETUP] readiness precondition lost");
          if(m_wvalid_o!==1'b1) wait_count++;
          if(wait_count==limit_cycles) begin
            $display("[UNIT_EVIDENCE] mode=%s beats=%0d accepted=%0d t_ns=%0.3f data_vld=%b len_vld=%b WVALID=%b WREADY=%b cycles=%0d",
              mode,beats,accepted,$realtime,atx_wdata_vld,dut.wdata_len_vld,m_wvalid_o,m_wready_i,wait_count);
            $fflush(fd);
            $fatal(1,"[WVALID_READY_DEPENDENCY] unit Slave waited for WVALID with data and length available");
          end
        end while(m_wvalid_o!==1'b1);
        // A compliant DUT must hold its first presentation while stalled.
        repeat(2) begin
          @(posedge clk);
          if(m_wvalid_o!==1 || m_wdata_o!==expected_data || m_wlast_o!==(n==beats-1))
            $fatal(1,"[UNIT_HOLD_FAIL] stalled VALID/data/LAST");
        end
        @(negedge clk);
      end
      m_wready_i=1;
      do @(posedge clk); while(m_wvalid_o!==1'b1);
      if(m_wdata_o!==expected_data || m_wlast_o!==(n==beats-1) || atx_wdata_rdy!==1)
        $fatal(1,"[UNIT_DATA_FAIL] beat=%0d",n);
      accepted++;
      @(negedge clk); atx_wdata_vld=0; m_wready_i=0;
    end
    repeat(3) @(posedge clk);
    if(accepted!=beats || dut.wdata_len_vld!==0 || m_wvalid_o!==0)
      $fatal(1,"[UNIT_DRAIN_FAIL]");
    $display("[UNIT_PASS] mode=%s beats=%0d accepted=%0d",mode,beats,accepted);
    $finish;
  end
  always @(posedge clk) if(rst_n)
    $fdisplay(fd,"%0.3f,%0d,%b,%b,%b,%b,%b,%b",$realtime,accepted,atx_wdata_vld,
      dut.wdata_len_vld,atx_wdata_rdy,m_wvalid_o,m_wready_i,m_wlast_o);
  initial begin #20000; $fatal(1,"[UNIT_GLOBAL_TIMEOUT]"); end
  final $fclose(fd);
endmodule
