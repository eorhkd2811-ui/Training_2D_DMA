// DPI boundary for tb_ref.cpp. Compile this package before scoreboard/top.
// Fixed scope: 2 channels, 256-bit beats, BYTE addresses and BYTE row strides.
// reset/seed/expect/check return 1 for success, 0 for failure.
// x_words/y_rows are actual counts, NOT the count-minus-one CSR encodings.
// *_incr=1: base + row*stride + column*32; *_incr=0: constant address.
// checked counts all observed beats; errors counts failures separately.
// Check $isunknown on each SV observation before conversion to the 2-state
// bit-vector DPI type, otherwise X/Z information is lost at this boundary.
package tb_dpi;
    import "DPI-C" function int dma_ref_reset();
    import "DPI-C" function int dma_ref_seed(input int unsigned byte_addr, input bit [255:0] data);
    import "DPI-C" function int dma_ref_expect(
        input int channel,
        input int unsigned src, input int unsigned dst,
        input int x_words, input int y_rows,
        input int src_stride, input int dst_stride,
        input int src_incr, input int dst_incr);
    import "DPI-C" function int dma_ref_check(input int channel, input int unsigned dst, input bit [255:0] actual);
    import "DPI-C" function int dma_ref_remaining(input int channel);
    import "DPI-C" function int dma_ref_checked(input int channel);
    import "DPI-C" function int dma_ref_errors();
    import "DPI-C" function void dma_ref_report();
    // Burst predictor: aligned INCR/INCR, equal 32-byte beats, finite 2D only.
    // Configure from the SAME channel values written to CSR, before SUBMIT.
    import "DPI-C" function int dma_pred_config(input int channel, input int id,
        input int max_beats, input int src_burst, input int dst_burst,
        input int beat_bytes);
    import "DPI-C" function int dma_pred_expect(input int channel,
        input int unsigned src, input int unsigned dst,
        input int x_words, input int y_rows, input int src_stride, input int dst_stride);
    import "DPI-C" function int dma_pred_channel(input int id);
    import "DPI-C" function int dma_pred_check(input int is_write, input int id,
        input int unsigned address, input int len, input int size, input int burst);
    import "DPI-C" function int dma_pred_pending(input int channel, input int is_write);
    import "DPI-C" function int dma_pred_finish();
    import "DPI-C" function void dma_pred_report();
endpackage
