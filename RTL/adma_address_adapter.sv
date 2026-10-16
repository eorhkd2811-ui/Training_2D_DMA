module adma_address_adapter
#(
    parameter DMA_BASE_ADDR = 32'h8000_0000,
    parameter DMA_CHN_NUM   = 4,
    parameter S_DATA_W      = 32,
    parameter S_ADDR_W      = 32
) (
    // AXI byte-addressed address
    input  [S_ADDR_W-1:0] s_awaddr_i,
    input  [S_ADDR_W-1:0] s_araddr_i,

    // DMA register-index address
    output [S_ADDR_W-1:0] m_awaddr_o,
    output [S_ADDR_W-1:0] m_araddr_o,

    // Address alignment
    output                awaddr_aligned_o,
    output                araddr_aligned_o
);

    localparam ADDR_SHIFT = $clog2(S_DATA_W / 8);
    localparam CHN_STRIDE = 16 * (S_DATA_W / 8);

    localparam RW_REG_ADDR =
        DMA_BASE_ADDR + 32'h0000_0000;

    localparam RW1S_REG_ADDR =
        DMA_BASE_ADDR + 32'h0000_1000;

    localparam RO_REG_ADDR =
        DMA_BASE_ADDR + 32'h0000_2000;

    localparam RW_REG_END =
        RW_REG_ADDR + DMA_CHN_NUM * CHN_STRIDE;

    localparam RW1S_REG_END =
        RW1S_REG_ADDR + DMA_CHN_NUM * CHN_STRIDE;

    localparam RO_REG_END =
        RO_REG_ADDR + DMA_CHN_NUM * CHN_STRIDE;


    function automatic [S_ADDR_W-1:0] translate_addr;

        input [S_ADDR_W-1:0] addr;

        begin
            translate_addr = addr;

            // Read-Write register region
            if ((addr >= RW_REG_ADDR) && (addr <  RW_REG_END)) begin
                translate_addr = RW_REG_ADDR + ((addr - RW_REG_ADDR) >> ADDR_SHIFT);
            end

            // Write-to-set register region
            else if ((addr >= RW1S_REG_ADDR) && (addr <  RW1S_REG_END)) begin
                translate_addr = RW1S_REG_ADDR + ((addr - RW1S_REG_ADDR) >> ADDR_SHIFT);
            end

            // Read-only register region
            else if ((addr >= RO_REG_ADDR) && (addr <  RO_REG_END)) begin
                translate_addr = RO_REG_ADDR + ((addr - RO_REG_ADDR) >> ADDR_SHIFT);
            end
        end

    endfunction


    assign m_awaddr_o = translate_addr(s_awaddr_i);
    assign m_araddr_o = translate_addr(s_araddr_i);

    assign awaddr_aligned_o = (s_awaddr_i[ADDR_SHIFT-1:0] == {ADDR_SHIFT{1'b0}});

    assign araddr_aligned_o = (s_araddr_i[ADDR_SHIFT-1:0] == {ADDR_SHIFT{1'b0}});

endmodule