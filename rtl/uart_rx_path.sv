/*
 * UART RX Path Integration
 *
 * Integrates UART receiver with async RX FIFO for buffered reception.
 * Includes bit synchronizer for the RX serial input.
 *
 * Clock Domains:
 *   - uart_clk: UART clock domain (for receiver and FIFO write)
 *   - rd_clk: Read interface (to register file, typically AXI clock)
 *
 * Parameters:
 *   FIFO_DEPTH - RX FIFO depth, must be power of 2 (default: 8)
 *   DATA_WIDTH - Data width (default: 8)
 */

module uart_rx_path #(
    parameter int FIFO_DEPTH = 8,
    parameter int DATA_WIDTH = 8
) (
    // UART clock domain
    input  logic                    uart_clk,
    input  logic                    uart_rst_n,
    input  logic                    sample_tick,

    // Serial input (asynchronous)
    input  logic                    rx_serial,

    // Read clock domain (to registers)
    input  logic                    rd_clk,
    input  logic                    rd_rst_n,
    output logic [DATA_WIDTH-1:0]   rd_data,
    input  logic                    rd_en,
    output logic                    rd_empty,

    // Status (in uart_clk domain, needs sync to rd_clk if used)
    output logic                    rx_full,
    output logic                    rx_active,
    output logic [3:0]              rx_level,
    output logic                    frame_error,
    output logic                    overrun_error,

    // Control (from rd_clk domain)
    input  logic                    fifo_reset
);

    // Synchronized RX serial input
    logic rx_serial_sync;

    // RX core signals
    logic [DATA_WIDTH-1:0] rx_data_core;
    logic                  rx_valid_core;
    logic                  rx_ready_core;
    logic                  frame_error_core;

    // FIFO signals in uart_clk domain
    logic                  fifo_wr_full;
    logic                  fifo_wr_en;

    // Overrun error (sticky)
    logic                  overrun_error_reg;

    // Note: fifo_reset input is ignored - async FIFO uses rst_n signals directly
    // SW can clear FIFO by disabling/re-enabling RX in the control register

    //--------------------------------------------------------------------------
    // Bit Synchronizer for RX Input
    //--------------------------------------------------------------------------

    bit_sync #(
        .STAGES (3)  // 3 stages for extra safety on external signal
    ) rx_sync (
        .clk_dst    (uart_clk),
        .rst_n_dst  (uart_rst_n),
        .data_in    (rx_serial),
        .data_out   (rx_serial_sync)
    );

    //--------------------------------------------------------------------------
    // RX Core
    //--------------------------------------------------------------------------

    uart_rx #(
        .DATA_WIDTH      (DATA_WIDTH),
        .OVERSAMPLE_RATE (16)
    ) rx_core (
        .uart_clk       (uart_clk),
        .rst_n          (uart_rst_n),
        .sample_tick    (sample_tick),
        .rx_serial_sync (rx_serial_sync),
        .rx_data        (rx_data_core),
        .rx_valid       (rx_valid_core),
        .rx_ready       (rx_ready_core),
        .frame_error    (frame_error_core),
        .rx_active      (rx_active)
    );

    //--------------------------------------------------------------------------
    // RX Async FIFO
    //--------------------------------------------------------------------------

    async_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (FIFO_DEPTH)
    ) rx_fifo (
        // Write interface (uart_clk domain)
        .wr_clk         (uart_clk),
        .wr_rst_n       (uart_rst_n),
        .wr_en          (fifo_wr_en),
        .wr_data        (rx_data_core),
        .wr_full        (fifo_wr_full),
        .wr_almost_full (),

        // Read interface (rd_clk domain)
        .rd_clk         (rd_clk),
        .rd_rst_n       (rd_rst_n),
        .rd_en          (rd_en),
        .rd_data        (rd_data),
        .rd_empty       (rd_empty),
        .rd_almost_empty()
    );

    //--------------------------------------------------------------------------
    // Control Logic
    //--------------------------------------------------------------------------

    // Write to FIFO when RX core has valid data
    assign fifo_wr_en = rx_valid_core && !fifo_wr_full;
    assign rx_ready_core = !fifo_wr_full;

    // synthesis translate_off
    always @(posedge uart_clk) begin
        if (fifo_wr_en) begin
            $display("[uart_rx_path] %0t: Writing 0x%h to RX FIFO", $time, rx_data_core);
        end
    end
    // synthesis translate_on

    // Overrun error: trying to write to full FIFO
    always_ff @(posedge uart_clk or negedge uart_rst_n) begin
        if (!uart_rst_n) begin
            overrun_error_reg <= 1'b0;
        end else if (rx_valid_core && fifo_wr_full) begin
            overrun_error_reg <= 1'b1;
        end
    end

    //--------------------------------------------------------------------------
    // Status Outputs (in uart_clk domain)
    //--------------------------------------------------------------------------

    assign rx_full = fifo_wr_full;
    assign frame_error = frame_error_core;
    assign overrun_error = overrun_error_reg;

    // rx_level: Approximate level based on write pointer
    // Note: This is in uart_clk domain. For accurate level in rd_clk domain,
    // would need to synchronize read pointer back, which async_fifo doesn't expose.
    // For now, use simple full/not-full indication
    assign rx_level = fifo_wr_full ? 4'd8 : 4'd1;

endmodule
