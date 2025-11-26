/*
 * UART TX Path
 *
 * Complete transmit datapath integrating FIFO and uart_tx serializer.
 * Provides buffered transmission with automatic drain.
 *
 * Features:
 * - Buffered transmission (8-byte FIFO)
 * - Automatic drain from FIFO to uart_tx
 * - Status flags (empty, full, active, level)
 * - Simple write interface
 *
 * Architecture:
 *   wr_data → sync_fifo → uart_tx → tx_serial
 *   wr_en               (auto drain)
 *
 * Usage:
 *   uart_tx_path tx_path (
 *       .uart_clk   (uart_clk),
 *       .rst_n      (rst_n),
 *       .baud_tick  (baud_tick_16x),
 *       .wr_data    (data),
 *       .wr_en      (write_strobe),
 *       .tx_serial  (uart_tx_pin),
 *       .tx_empty   (fifo_empty),
 *       .tx_full    (fifo_full),
 *       .tx_active  (transmitting),
 *       .tx_level   (fifo_level)
 *   );
 *
 * IMPORTANT:
 * - Check tx_full before writing
 * - uart_tx automatically drains FIFO when not empty
 * - All signals in uart_clk domain (no CDC)
 *
 * References:
 * - INTERFACE_SPECIFICATIONS.md - Module 6: uart_tx_path
 */

module uart_tx_path #(
    parameter int FIFO_DEPTH = 8,
    parameter int DATA_WIDTH = 8
) (
    // Clock and reset
    input  logic                 uart_clk,
    input  logic                 rst_n,

    // Baud rate tick
    input  logic                 baud_tick,

    // Write interface (to FIFO)
    input  logic [DATA_WIDTH-1:0] wr_data,
    input  logic                  wr_en,

    // Serial output
    output logic                  tx_serial,

    // Status outputs
    output logic                  tx_empty,
    output logic                  tx_full,
    output logic                  tx_active,
    output logic [$clog2(FIFO_DEPTH):0] tx_level
);

    // FIFO signals
    logic [DATA_WIDTH-1:0] fifo_rd_data;
    logic                  fifo_rd_en;
    logic                  fifo_rd_empty;

    // uart_tx signals
    logic tx_ready;
    logic tx_valid;

    // TX FIFO instance
    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) tx_fifo (
        .clk       (uart_clk),
        .rst_n     (rst_n),
        .wr_en     (wr_en),
        .wr_data   (wr_data),
        .wr_full   (tx_full),
        .rd_en     (fifo_rd_en),
        .rd_data   (fifo_rd_data),
        .rd_empty  (fifo_rd_empty),
        .level     (tx_level)
    );

    // UART TX instance
    uart_tx #(
        .DATA_WIDTH(DATA_WIDTH),
        .OVERSAMPLE_RATE(16)
    ) tx_core (
        .uart_clk   (uart_clk),
        .rst_n      (rst_n),
        .baud_tick  (baud_tick),
        .tx_data    (fifo_rd_data),
        .tx_valid   (tx_valid),
        .tx_ready   (tx_ready),
        .tx_serial  (tx_serial),
        .tx_active  (tx_active)
    );

    // Data valid tracking for registered FIFO output
    // The sync_fifo has registered output (1-cycle latency)
    // We need to track when data is actually valid
    logic fifo_data_valid;

    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_data_valid <= 1'b0;
        end else begin
            // Data becomes valid 1 cycle after rd_en
            fifo_data_valid <= fifo_rd_en;
        end
    end

    // Automatic drain logic
    // Read from FIFO when: uart_tx is ready and (FIFO not empty and no pending read)
    assign fifo_rd_en = tx_ready && !fifo_rd_empty && !fifo_data_valid;
    assign tx_valid = fifo_data_valid;

    // Pass through empty flag
    assign tx_empty = fifo_rd_empty;

    // Assertions for verification
`ifdef SIMULATION
    initial begin
        // Check FIFO_DEPTH is power of 2
        assert ((FIFO_DEPTH & (FIFO_DEPTH - 1)) == 0 && FIFO_DEPTH > 0)
            else $error("uart_tx_path: FIFO_DEPTH must be power of 2");

        assert (DATA_WIDTH == 8)
            else $error("uart_tx_path: Only DATA_WIDTH=8 supported");
    end

    // Runtime assertions
    always_ff @(posedge uart_clk) begin
        if (rst_n) begin
            // Level should never exceed FIFO_DEPTH
            assert (tx_level <= FIFO_DEPTH)
                else $error("uart_tx_path: tx_level=%0d exceeds FIFO_DEPTH=%0d",
                           tx_level, FIFO_DEPTH);

            // Empty and full should be mutually exclusive
            assert (!(tx_empty && tx_full))
                else $error("uart_tx_path: Cannot be both empty and full");

            // If empty, level should be 0
            if (tx_empty) begin
                assert (tx_level == 0)
                    else $error("uart_tx_path: Empty but level=%0d", tx_level);
            end

            // If full, level should be FIFO_DEPTH
            if (tx_full) begin
                assert (tx_level == FIFO_DEPTH)
                    else $error("uart_tx_path: Full but level=%0d", tx_level);
            end
        end
    end
`endif

endmodule
