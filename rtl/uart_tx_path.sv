/*
 * UART TX Path Integration
 *
 * Integrates TX FIFO with UART transmitter for buffered transmission.
 * Automatically transmits data from FIFO when available.
 *
 * Parameters:
 *   FIFO_DEPTH - TX FIFO depth (default: 8)
 *   DATA_WIDTH - Data width (default: 8)
 */

module uart_tx_path #(
    parameter int FIFO_DEPTH = 8,
    parameter int DATA_WIDTH = 8
) (
    input  logic                    uart_clk,
    input  logic                    rst_n,
    input  logic                    baud_tick,

    // FIFO write interface (from registers)
    input  logic [DATA_WIDTH-1:0]   wr_data,
    input  logic                    wr_en,

    // Serial output
    output logic                    tx_serial,

    // Status
    output logic                    tx_empty,
    output logic                    tx_full,
    output logic                    tx_active,
    output logic [3:0]              tx_level,

    // Control
    input  logic                    fifo_reset
);

    // FIFO signals
    logic [DATA_WIDTH-1:0] fifo_rd_data;
    logic                  fifo_rd_en;
    logic                  fifo_wr_en_internal;
    logic                  wr_en_prev;
    logic                  fifo_empty;
    logic                  fifo_full;

    // TX core signals
    logic                  tx_valid;
    logic                  tx_ready;

    // Edge detector for wr_en to prevent multiple writes
    // wr_en comes from clk domain, need to prevent multiple pushes in uart_clk domain
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_en_prev <= 1'b0;
        end else begin
            wr_en_prev <= wr_en;
        end
    end

    assign fifo_wr_en_internal = wr_en && !wr_en_prev;

    // TX FIFO
    sync_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (FIFO_DEPTH)
    ) tx_fifo (
        .clk         (uart_clk),
        .rst_n       (rst_n && !fifo_reset),
        .wr_en       (fifo_wr_en_internal),
        .wr_data     (wr_data),
        .full        (fifo_full),
        .almost_full (),
        .rd_en       (fifo_rd_en),
        .rd_data     (fifo_rd_data),
        .empty       (fifo_empty),
        .almost_empty(),
        .level       (tx_level)
    );

    // TX core
    uart_tx #(
        .DATA_WIDTH (DATA_WIDTH)
    ) tx_core (
        .uart_clk    (uart_clk),
        .rst_n       (rst_n),
        .baud_tick   (baud_tick),
        .tx_data     (fifo_rd_data),
        .tx_valid    (tx_valid),
        .tx_ready    (tx_ready),
        .tx_serial   (tx_serial),
        .tx_active   (tx_active)
    );

    // Control logic: read from FIFO when TX core is ready
    assign tx_valid = !fifo_empty;
    assign fifo_rd_en = tx_ready && !fifo_empty && baud_tick;

    // Status outputs
    assign tx_empty = fifo_empty;
    assign tx_full = fifo_full;

endmodule
