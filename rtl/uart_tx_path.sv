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

    // Prefetch holding register for TX data
    // FIFO has registered output: rd_data valid 1 cycle after rd_en
    // Use holding register that prefetches data so it's always ready
    logic [DATA_WIDTH-1:0] tx_holding_reg;
    logic                  tx_holding_valid;
    logic                  tx_data_accepted;  // Track if uart_tx has accepted the current data

    // State: IDLE -> FETCHING -> READY
    typedef enum logic [1:0] {
        TX_IDLE     = 2'b00,  // No data available
        TX_FETCHING = 2'b01,  // Requested data from FIFO, waiting 1 cycle
        TX_READY    = 2'b10   // Data in holding register, ready to transmit
    } tx_state_t;

    tx_state_t tx_state;

    // fifo_reset provides software control to clear FIFO pointers
    // Connected to async FIFO's wr_clear input for synchronous reset

    //--------------------------------------------------------------------------
    // TX Async FIFO
    //--------------------------------------------------------------------------

    async_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (FIFO_DEPTH)
    ) tx_fifo (
        // Write interface (wr_clk domain)
        .wr_clk         (wr_clk),
        .wr_rst_n       (wr_rst_n),
        .wr_clear       (fifo_reset),   // Software FIFO clear
        .wr_en          (wr_en),
        .wr_data        (wr_data),
        .wr_full        (wr_full),
        .wr_almost_full (),

        // Read interface (uart_clk domain)
        .rd_clk         (uart_clk),
        .rd_rst_n       (uart_rst_n),
        .rd_clear       (1'b0),         // No clear on read side for TX FIFO
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
        .tx_data     (tx_holding_reg),  // Use holding register, not FIFO directly
        .tx_valid    (tx_valid),
        .tx_ready    (tx_ready),
        .tx_serial   (tx_serial),
        .tx_active   (tx_active)
    );

    //--------------------------------------------------------------------------
    // Prefetch Holding Register FSM
    //--------------------------------------------------------------------------

    always_ff @(posedge uart_clk or negedge uart_rst_n) begin
        if (!uart_rst_n) begin
            tx_holding_reg <= '0;
            tx_holding_valid <= 1'b0;
            tx_data_accepted <= 1'b0;
            tx_state <= TX_IDLE;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx_data_accepted <= 1'b0;
                    // Start fetch when FIFO has data
                    if (!fifo_rd_empty) begin
                        tx_state <= TX_FETCHING;
                        // synthesis translate_off
                        $display("[uart_tx_path] %0t: TX_IDLE -> TX_FETCHING (fifo_rd_empty=%b)", $time, fifo_rd_empty);
                        // synthesis translate_on
                    end
                end

                TX_FETCHING: begin
                    // Capture data after 1-cycle FIFO latency
                    tx_holding_reg <= fifo_rd_data;
                    tx_holding_valid <= 1'b1;
                    tx_data_accepted <= 1'b0;
                    tx_state <= TX_READY;
                    // synthesis translate_off
                    $display("[uart_tx_path] %0t: TX_FETCHING -> TX_READY (data=0x%h)", $time, fifo_rd_data);
                    // synthesis translate_on
                end

                TX_READY: begin
                    // Track transmission lifecycle:
                    // 1. tx_active goes HIGH: uart_tx started, set tx_data_accepted
                    // 2. tx_active goes LOW after being HIGH: transmission complete, clear holding register
                    if (tx_active && !tx_data_accepted) begin
                        // uart_tx has started transmission
                        tx_data_accepted <= 1'b1;
                        // synthesis translate_off
                        $display("[uart_tx_path] %0t: TX started (tx_active went HIGH)", $time);
                        // synthesis translate_on
                    end else if (!tx_active && tx_data_accepted) begin
                        // uart_tx was active, now back to idle - transmission complete
                        tx_holding_valid <= 1'b0;
                        tx_data_accepted <= 1'b0;
                        // synthesis translate_off
                        $display("[uart_tx_path] %0t: TX completed (tx_active went LOW, data=0x%h, fifo_rd_empty=%b)",
                                 $time, tx_holding_reg, fifo_rd_empty);
                        // synthesis translate_on
                        // If more data available, start next fetch immediately
                        if (!fifo_rd_empty) begin
                            tx_state <= TX_FETCHING;
                        end else begin
                            tx_state <= TX_IDLE;
                        end
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // Assert rd_en when entering FETCHING state
    assign fifo_rd_en = (tx_state == TX_IDLE) && !fifo_rd_empty;

    // TX valid when holding register has data
    assign tx_valid = tx_holding_valid;

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
