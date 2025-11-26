/*
 * UART RX Path
 *
 * Complete receive datapath: bit_sync + uart_rx + FIFO
 * Automatically receives serial data and buffers in FIFO for software reads.
 *
 * Architecture:
 *   rx_serial (async) → bit_sync → uart_rx → sync_fifo → rd_data
 *                        (2-FF)     (8N1)     (buffered)
 *
 * Features:
 * - Automatic reception (no manual control needed)
 * - Async input synchronization via bit_sync
 * - Buffered reception via FIFO
 * - Frame error detection (invalid stop bit)
 * - Overrun error detection (FIFO full when new data arrives)
 * - Duplicate write prevention (one byte per rx_valid assertion)
 *
 * Usage:
 *   uart_rx_path #(
 *       .FIFO_DEPTH(8),
 *       .DATA_WIDTH(8)
 *   ) rx_path_inst (
 *       .uart_clk      (uart_clk),
 *       .rst_n         (rst_n),
 *       .sample_tick   (sample_tick_16x),
 *       .rx_serial     (uart_rx_pin),  // Async input - will be synchronized
 *       .rd_data       (rx_data),
 *       .rd_en         (read_enable),
 *       .rx_empty      (empty),
 *       .rx_full       (full),
 *       .rx_active     (receiving),
 *       .frame_error   (framing_error),
 *       .overrun_error (overrun_err),
 *       .rx_level      (fifo_level)
 *   );
 *
 * IMPORTANT:
 * - rx_serial is asynchronous and MUST be synchronized internally
 * - Duplicate write prevention ensures exactly one FIFO write per byte received
 * - Errors (frame_error, overrun_error) are sticky and must be cleared by software
 *
 * References:
 * - INTERFACE_SPECIFICATIONS.md - Module 7: uart_rx_path
 */

module uart_rx_path #(
    parameter int FIFO_DEPTH = 8,
    parameter int DATA_WIDTH = 8,
    parameter int SYNC_STAGES = 2
) (
    // Clock and reset
    input  logic                  uart_clk,
    input  logic                  rst_n,

    // Sample rate tick
    input  logic                  sample_tick,

    // Serial input (asynchronous!)
    input  logic                  rx_serial,

    // FIFO read interface
    output logic [DATA_WIDTH-1:0] rd_data,
    input  logic                  rd_en,

    // Status outputs
    output logic                  rx_empty,
    output logic                  rx_full,
    output logic                  rx_active,
    output logic                  frame_error,
    output logic                  overrun_error,
    output logic [$clog2(FIFO_DEPTH):0] rx_level
);

    // Internal signals
    logic                  rx_serial_sync;
    logic [DATA_WIDTH-1:0] rx_data_internal;
    logic                  rx_valid_internal;
    logic                  rx_ready_internal;
    logic                  frame_error_internal;
    logic                  rx_data_written;
    logic                  fifo_wr_en;
    logic                  overrun_error_reg;
    logic                  frame_error_reg;

    // =====================================================
    // Stage 1: Bit Synchronizer
    // =====================================================
    // Synchronize async rx_serial input to uart_clk domain
    // RESET_VALUE=1 because UART RX line idles high
    bit_sync #(
        .STAGES      (SYNC_STAGES),
        .RESET_VALUE (1'b1)
    ) rx_bit_sync (
        .clk_dst    (uart_clk),
        .rst_n_dst  (rst_n),
        .data_in    (rx_serial),
        .data_out   (rx_serial_sync)
    );

    // =====================================================
    // Stage 2: UART Receiver
    // =====================================================
    // Deserialize UART frames (8N1 format)
    uart_rx #(
        .DATA_WIDTH      (DATA_WIDTH),
        .OVERSAMPLE_RATE (16)
    ) uart_rx_inst (
        .uart_clk        (uart_clk),
        .rst_n           (rst_n),
        .sample_tick     (sample_tick),
        .rx_serial_sync  (rx_serial_sync),
        .rx_data         (rx_data_internal),
        .rx_valid        (rx_valid_internal),
        .rx_ready        (rx_ready_internal),
        .frame_error     (frame_error_internal),
        .rx_active       (rx_active)
    );

    // =====================================================
    // Stage 3: Duplicate Write Prevention
    // =====================================================
    // Ensure exactly ONE FIFO write per rx_valid assertion
    // Problem: rx_valid stays high until handshake, could write multiple times
    // Solution: Track if we've already written this byte
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_data_written <= 1'b0;
        end else begin
            if (rx_valid_internal && !rx_data_written && !rx_full) begin
                // First cycle of rx_valid and FIFO not full - mark as written
                rx_data_written <= 1'b1;
            end else if (!rx_valid_internal) begin
                // rx_valid dropped - clear flag for next byte
                rx_data_written <= 1'b0;
            end
        end
    end

    // Generate FIFO write enable: write on first cycle of rx_valid only
    assign fifo_wr_en = rx_valid_internal && !rx_data_written && !rx_full;

    // Generate rx_ready: handshake back to uart_rx
    // Ready when we've written to FIFO or when FIFO is full (discard)
    assign rx_ready_internal = rx_data_written || rx_full;

    // =====================================================
    // Stage 4: Overrun Error Detection
    // =====================================================
    // Detect when new data arrives but FIFO is full
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            overrun_error_reg <= 1'b0;
        end else begin
            if (rx_valid_internal && !rx_data_written && rx_full) begin
                // New byte arrived but FIFO is full - overrun!
                overrun_error_reg <= 1'b1;
            end
            // Sticky flag - software must clear via register write
        end
    end

    assign overrun_error = overrun_error_reg;

    // =====================================================
    // Stage 5: Frame Error Propagation
    // =====================================================
    // Make frame_error sticky (software must clear)
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_error_reg <= 1'b0;
        end else begin
            if (frame_error_internal) begin
                frame_error_reg <= 1'b1;
            end
            // Sticky flag - software must clear via register write
        end
    end

    assign frame_error = frame_error_reg;

    // =====================================================
    // Stage 6: RX FIFO
    // =====================================================
    // Buffer received bytes for software reads
    sync_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (FIFO_DEPTH)
    ) rx_fifo (
        .clk        (uart_clk),
        .rst_n      (rst_n),
        .wr_data    (rx_data_internal),
        .wr_en      (fifo_wr_en),
        .rd_data    (rd_data),
        .rd_en      (rd_en),
        .rd_empty   (rx_empty),
        .wr_full    (rx_full),
        .level      (rx_level)
    );

    // =====================================================
    // Assertions for Verification
    // =====================================================
`ifdef SIMULATION
    initial begin
        // Check parameters
        assert (DATA_WIDTH == 8)
            else $error("uart_rx_path: Only DATA_WIDTH=8 supported for 8N1");

        assert (FIFO_DEPTH > 0 && (FIFO_DEPTH & (FIFO_DEPTH - 1)) == 0)
            else $error("uart_rx_path: FIFO_DEPTH must be power of 2");

        assert (SYNC_STAGES >= 2)
            else $warning("uart_rx_path: SYNC_STAGES < 2 may cause metastability");
    end

    // Runtime assertions
    always_ff @(posedge uart_clk) begin
        if (rst_n) begin
            // Should never write to FIFO when full
            assert (!(fifo_wr_en && rx_full))
                else $error("uart_rx_path: Attempted FIFO write when full");

            // rx_data_written should only be set when rx_valid is high
            assert (!rx_data_written || rx_valid_internal)
                else $error("uart_rx_path: rx_data_written high without rx_valid");

            // FIFO level should never exceed depth
            assert (rx_level <= FIFO_DEPTH)
                else $error("uart_rx_path: rx_level=%0d exceeds FIFO_DEPTH=%0d",
                           rx_level, FIFO_DEPTH);
        end
    end
`endif

endmodule
