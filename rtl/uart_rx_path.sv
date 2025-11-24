/*
 * UART RX Path Integration
 *
 * Integrates UART receiver with RX FIFO for buffered reception.
 * Includes bit synchronizer for the RX serial input.
 *
 * Parameters:
 *   FIFO_DEPTH - RX FIFO depth (default: 8)
 *   DATA_WIDTH - Data width (default: 8)
 */

module uart_rx_path #(
    parameter int FIFO_DEPTH = 8,
    parameter int DATA_WIDTH = 8
) (
    input  logic                    uart_clk,
    input  logic                    rst_n,
    input  logic                    sample_tick,

    // Serial input (asynchronous)
    input  logic                    rx_serial,

    // FIFO read interface (to registers)
    output logic [DATA_WIDTH-1:0]   rd_data,
    input  logic                    rd_en,

    // Status
    output logic                    rx_empty,
    output logic                    rx_full,
    output logic                    rx_active,
    output logic [3:0]              rx_level,
    output logic                    frame_error,
    output logic                    overrun_error,

    // Control
    input  logic                    fifo_reset
);

    // Synchronized RX serial input
    logic rx_serial_sync;

    // RX core signals
    logic [DATA_WIDTH-1:0] rx_data_core;
    logic                  rx_valid_core;
    logic                  rx_ready_core;
    logic                  frame_error_core;

    // FIFO signals
    logic                  fifo_wr_en;
    logic                  fifo_full;
    logic                  fifo_empty;

    // Overrun error (sticky)
    logic                  overrun_error_reg;

    // Bit synchronizer for RX input
    bit_sync #(
        .STAGES (3)  // 3 stages for extra safety on external signal
    ) rx_sync (
        .clk_dst    (uart_clk),
        .rst_n_dst  (rst_n),
        .data_in    (rx_serial),
        .data_out   (rx_serial_sync)
    );

    // RX core
    uart_rx #(
        .DATA_WIDTH      (DATA_WIDTH),
        .OVERSAMPLE_RATE (16)
    ) rx_core (
        .uart_clk       (uart_clk),
        .rst_n          (rst_n),
        .sample_tick    (sample_tick),
        .rx_serial_sync (rx_serial_sync),
        .rx_data        (rx_data_core),
        .rx_valid       (rx_valid_core),
        .rx_ready       (rx_ready_core),
        .frame_error    (frame_error_core),
        .rx_active      (rx_active)
    );

    // RX FIFO
    sync_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (FIFO_DEPTH)
    ) rx_fifo (
        .clk         (uart_clk),
        .rst_n       (rst_n && !fifo_reset),
        .wr_en       (fifo_wr_en),
        .wr_data     (rx_data_core),
        .full        (fifo_full),
        .almost_full (),
        .rd_en       (rd_en),
        .rd_data     (rd_data),
        .empty       (fifo_empty),
        .almost_empty(),
        .level       (rx_level)
    );

    // Control logic: write to FIFO when RX core has valid data
    assign fifo_wr_en = rx_valid_core && !fifo_full;
    assign rx_ready_core = !fifo_full;

    // Overrun error: trying to write to full FIFO
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n || fifo_reset) begin
            overrun_error_reg <= 1'b0;
        end else if (rx_valid_core && fifo_full) begin
            overrun_error_reg <= 1'b1;
        end
    end

    // Status outputs
    assign rx_empty = fifo_empty;
    assign rx_full = fifo_full;
    assign frame_error = frame_error_core;
    assign overrun_error = overrun_error_reg;

endmodule
