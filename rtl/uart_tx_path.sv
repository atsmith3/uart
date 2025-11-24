/*
 * UART TX Path Integration
 *
 * Integrates async TX FIFO with UART transmitter for buffered transmission.
 * Automatically transmits data from FIFO when available.
 *
 * Clock Domains:
 *   - wr_clk: Write interface (from register file, typically AXI clock)
 *   - uart_clk: UART clock domain (for transmitter and FIFO read)
 *
 * Parameters:
 *   FIFO_DEPTH - TX FIFO depth, must be power of 2 (default: 8)
 *   DATA_WIDTH - Data width (default: 8)
 */

module uart_tx_path #(
    parameter int FIFO_DEPTH = 8,
    parameter int DATA_WIDTH = 8
) (
    // Write clock domain (from registers)
    input  logic                    wr_clk,
    input  logic                    wr_rst_n,
    input  logic [DATA_WIDTH-1:0]   wr_data,
    input  logic                    wr_en,
    output logic                    wr_full,

    // UART clock domain
    input  logic                    uart_clk,
    input  logic                    uart_rst_n,
    input  logic                    baud_tick,

    // Serial output
    output logic                    tx_serial,

    // Status (in uart_clk domain, needs sync to wr_clk if used)
    output logic                    tx_empty,
    output logic                    tx_active,
    output logic [3:0]              tx_level,

    // Control (from wr_clk domain)
    input  logic                    fifo_reset
);

    // FIFO signals in uart_clk domain
    logic [DATA_WIDTH-1:0] fifo_rd_data;
    logic                  fifo_rd_en;
    logic                  fifo_rd_empty;

    // TX core signals
    logic                  tx_valid;
    logic                  tx_ready;

    // Synchronized reset for FIFO write side
    logic wr_rst_n_sync;
    assign wr_rst_n_sync = wr_rst_n && !fifo_reset;

    // Synchronized reset for FIFO read side
    logic uart_rst_n_sync;
    assign uart_rst_n_sync = uart_rst_n && !fifo_reset;

    //--------------------------------------------------------------------------
    // TX Async FIFO
    //--------------------------------------------------------------------------

    async_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (FIFO_DEPTH)
    ) tx_fifo (
        // Write interface (wr_clk domain)
        .wr_clk         (wr_clk),
        .wr_rst_n       (wr_rst_n_sync),
        .wr_en          (wr_en),
        .wr_data        (wr_data),
        .wr_full        (wr_full),
        .wr_almost_full (),

        // Read interface (uart_clk domain)
        .rd_clk         (uart_clk),
        .rd_rst_n       (uart_rst_n_sync),
        .rd_en          (fifo_rd_en),
        .rd_data        (fifo_rd_data),
        .rd_empty       (fifo_rd_empty),
        .rd_almost_empty()
    );

    //--------------------------------------------------------------------------
    // TX Core
    //--------------------------------------------------------------------------

    uart_tx #(
        .DATA_WIDTH (DATA_WIDTH)
    ) tx_core (
        .uart_clk    (uart_clk),
        .rst_n       (uart_rst_n),
        .baud_tick   (baud_tick),
        .tx_data     (fifo_rd_data),
        .tx_valid    (tx_valid),
        .tx_ready    (tx_ready),
        .tx_serial   (tx_serial),
        .tx_active   (tx_active)
    );

    //--------------------------------------------------------------------------
    // Control Logic
    //--------------------------------------------------------------------------

    // Read from FIFO when TX core is ready
    assign tx_valid = !fifo_rd_empty;
    assign fifo_rd_en = tx_ready && !fifo_rd_empty && baud_tick;

    //--------------------------------------------------------------------------
    // Status Outputs (in uart_clk domain)
    //--------------------------------------------------------------------------

    assign tx_empty = fifo_rd_empty;

    // tx_level: Approximate level based on read pointer
    // Note: This is in uart_clk domain. For accurate level in wr_clk domain,
    // would need to synchronize write pointer back, which async_fifo doesn't expose.
    // For now, use simple empty/not-empty indication
    assign tx_level = fifo_rd_empty ? 4'd0 : 4'd1;

endmodule
