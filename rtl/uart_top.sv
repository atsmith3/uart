/*
 * UART Top-Level Module
 *
 * Complete UART peripheral integrating all components:
 * - uart_regs: Register file
 * - baud_gen: Baud rate generator
 * - uart_tx_path: Transmit datapath (FIFO + TX)
 * - uart_rx_path: Receive datapath (bit_sync + RX + FIFO)
 *
 * Architecture:
 *   Register Interface → uart_regs → {baud_gen, uart_tx_path, uart_rx_path}
 *                                      ↓           ↓              ↓
 *                                   baud_tick   uart_tx       uart_rx
 *
 * Features:
 * - Complete UART peripheral with register interface
 * - 8N1 format (8 data bits, no parity, 1 stop bit)
 * - Configurable baud rate via divisor
 * - TX/RX FIFOs for buffering
 * - Interrupt generation
 * - Error detection (frame, overrun)
 * - All logic in single uart_clk domain (simplified)
 *
 * Usage:
 *   uart_top #(
 *       .TX_FIFO_DEPTH(8),
 *       .RX_FIFO_DEPTH(8)
 *   ) uart_inst (
 *       .uart_clk    (clk),
 *       .rst_n       (rst_n),
 *       .reg_addr    (addr),
 *       .reg_wdata   (wdata),
 *       .reg_wen     (wen),
 *       .reg_ren     (ren),
 *       .reg_rdata   (rdata),
 *       .reg_error   (error),
 *       .uart_tx     (tx_pin),
 *       .uart_rx     (rx_pin),
 *       .irq         (interrupt)
 *   );
 *
 * References:
 * - INTERFACE_SPECIFICATIONS.md - Module 10: uart_top
 */

module uart_top #(
    parameter int DATA_WIDTH = 32,
    parameter int TX_FIFO_DEPTH = 8,
    parameter int RX_FIFO_DEPTH = 8
) (
    // Clock and reset
    input  logic                    uart_clk,
    input  logic                    rst_n,

    // Register interface (simplified, no AXI for testing)
    input  logic [3:0]              reg_addr,
    input  logic [DATA_WIDTH-1:0]   reg_wdata,
    input  logic                    reg_wen,
    input  logic                    reg_ren,
    output logic [DATA_WIDTH-1:0]   reg_rdata,
    output logic                    reg_error,

    // UART serial interface
    output logic                    uart_tx,
    input  logic                    uart_rx,

    // Interrupt output
    output logic                    irq
);

    // ========================================
    // Local Parameters
    // ========================================
    localparam int TX_FIFO_ADDR_WIDTH = $clog2(TX_FIFO_DEPTH);
    localparam int RX_FIFO_ADDR_WIDTH = $clog2(RX_FIFO_DEPTH);

    // ========================================
    // Internal Signals
    // ========================================

    // Baud generator
    logic [15:0] baud_divisor;
    logic        baud_enable;
    logic        baud_tick;

    // TX path
    logic [7:0]  wr_data;
    logic        wr_en;
    logic        tx_empty;
    logic        tx_full;
    logic        tx_active;
    logic [TX_FIFO_ADDR_WIDTH:0] tx_level;

    // RX path
    logic [7:0]  rx_data;
    logic        rd_en;
    logic        rx_empty;
    logic        rx_full;
    logic        rx_active;
    logic [RX_FIFO_ADDR_WIDTH:0] rx_level;
    logic        frame_error;
    logic        overrun_error;

    // FIFO control
    logic        tx_fifo_rst;
    logic        rx_fifo_rst;

    // ========================================
    // Module: uart_regs
    // ========================================
    // Register file connecting register interface to UART paths
    uart_regs #(
        .DATA_WIDTH       (DATA_WIDTH),
        .FIFO_ADDR_WIDTH  ($clog2(TX_FIFO_DEPTH > RX_FIFO_DEPTH ? TX_FIFO_DEPTH : RX_FIFO_DEPTH))
    ) uart_regs_inst (
        .uart_clk       (uart_clk),
        .rst_n          (rst_n),
        // Register interface
        .reg_addr       (reg_addr),
        .reg_wdata      (reg_wdata),
        .reg_wen        (reg_wen),
        .reg_ren        (reg_ren),
        .reg_rdata      (reg_rdata),
        .reg_error      (reg_error),
        // TX path interface
        .wr_data        (wr_data),
        .wr_en          (wr_en),
        .tx_empty       (tx_empty),
        .tx_full        (tx_full),
        .tx_active      (tx_active),
        .tx_level       (tx_level),
        // RX path interface
        .rx_data        (rx_data),
        .rd_en          (rd_en),
        .rx_empty       (rx_empty),
        .rx_full        (rx_full),
        .rx_active      (rx_active),
        .rx_level       (rx_level),
        .frame_error    (frame_error),
        .overrun_error  (overrun_error),
        // Baud generator interface
        .baud_divisor   (baud_divisor),
        .baud_enable    (baud_enable),
        // FIFO control
        .tx_fifo_rst    (tx_fifo_rst),
        .rx_fifo_rst    (rx_fifo_rst),
        // Interrupt output
        .irq            (irq)
    );

    // ========================================
    // Module: baud_gen
    // ========================================
    // Baud rate generator producing sample tick for TX/RX
    baud_gen baud_gen_inst (
        .uart_clk       (uart_clk),
        .rst_n          (rst_n),
        .baud_divisor   (baud_divisor),
        .enable         (baud_enable),
        .baud_tick      (baud_tick)
    );

    // ========================================
    // Module: uart_tx_path
    // ========================================
    // TX datapath: FIFO + uart_tx
    uart_tx_path #(
        .FIFO_DEPTH     (TX_FIFO_DEPTH),
        .DATA_WIDTH     (8)
    ) uart_tx_path_inst (
        .uart_clk       (uart_clk),
        .rst_n          (rst_n && !tx_fifo_rst),  // Allow FIFO reset
        .baud_tick      (baud_tick),
        // FIFO write interface
        .wr_data        (wr_data),
        .wr_en          (wr_en),
        // Status outputs
        .tx_empty       (tx_empty),
        .tx_full        (tx_full),
        .tx_active      (tx_active),
        .tx_level       (tx_level),
        // Serial output
        .tx_serial      (uart_tx)
    );

    // ========================================
    // Module: uart_rx_path
    // ========================================
    // RX datapath: bit_sync + uart_rx + FIFO
    uart_rx_path #(
        .FIFO_DEPTH     (RX_FIFO_DEPTH),
        .DATA_WIDTH     (8),
        .SYNC_STAGES    (2)
    ) uart_rx_path_inst (
        .uart_clk       (uart_clk),
        .rst_n          (rst_n && !rx_fifo_rst),  // Allow FIFO reset
        .sample_tick    (baud_tick),
        // Serial input (async)
        .rx_serial      (uart_rx),
        // FIFO read interface
        .rd_data        (rx_data),
        .rd_en          (rd_en),
        // Status outputs
        .rx_empty       (rx_empty),
        .rx_full        (rx_full),
        .rx_active      (rx_active),
        .frame_error    (frame_error),
        .overrun_error  (overrun_error),
        .rx_level       (rx_level)
    );

    // ========================================
    // Assertions for Verification
    // ========================================
`ifdef SIMULATION
    initial begin
        // Check parameters
        assert (DATA_WIDTH == 32)
            else $error("uart_top: Only DATA_WIDTH=32 supported");

        assert (TX_FIFO_DEPTH > 0 && (TX_FIFO_DEPTH & (TX_FIFO_DEPTH - 1)) == 0)
            else $error("uart_top: TX_FIFO_DEPTH must be power of 2");

        assert (RX_FIFO_DEPTH > 0 && (RX_FIFO_DEPTH & (RX_FIFO_DEPTH - 1)) == 0)
            else $error("uart_top: RX_FIFO_DEPTH must be power of 2");
    end

    // Runtime assertions
    always_ff @(posedge uart_clk) begin
        if (rst_n) begin
            // uart_tx should never be X or Z
            assert (!$isunknown(uart_tx))
                else $error("uart_top: uart_tx is X or Z");

            // Baud tick should be single cycle pulse
            if (baud_tick) begin
                // No assertion here, just monitoring
            end
        end
    end
`endif

endmodule
