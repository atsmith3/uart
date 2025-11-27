/*
 * UART AXI Top-Level Module
 *
 * Complete UART peripheral with AXI-Lite interface.
 * Integrates AXI-Lite slave interface with UART core (uart_top).
 *
 * Architecture:
 *   AXI-Lite Bus → axi_lite_slave_if → Register Interface → uart_top → UART pins
 *
 * Features:
 * - Full AXI4-Lite slave interface (5 channels)
 * - 8N1 UART with configurable baud rate
 * - TX/RX FIFOs for buffering
 * - Interrupt generation
 * - Single clock domain (simplified for Phase 5.3, CDC in Phase 5.4)
 *
 * Usage:
 *   uart_axi_top #(
 *       .TX_FIFO_DEPTH(8),
 *       .RX_FIFO_DEPTH(8)
 *   ) uart_inst (
 *       .clk         (sys_clk),
 *       .rst_n       (rst_n),
 *       // AXI-Lite interface
 *       .awaddr      (s_axi_awaddr),
 *       .awvalid     (s_axi_awvalid),
 *       .awready     (s_axi_awready),
 *       // ... other AXI signals
 *       // UART pins
 *       .uart_tx     (uart_tx_pin),
 *       .uart_rx     (uart_rx_pin),
 *       .irq         (uart_irq)
 *   );
 *
 * References:
 * - UART_Implementation_Plan.md - Phase 5.3: AXI Integration
 */

module uart_axi_top #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32,
    parameter int TX_FIFO_DEPTH = 8,
    parameter int RX_FIFO_DEPTH = 8
) (
    // Clock and reset
    input  logic                    clk,
    input  logic                    rst_n,

    // AXI-Lite Write Address Channel
    input  logic [ADDR_WIDTH-1:0]   awaddr,
    input  logic                    awvalid,
    output logic                    awready,

    // AXI-Lite Write Data Channel
    input  logic [DATA_WIDTH-1:0]   wdata,
    input  logic [DATA_WIDTH/8-1:0] wstrb,
    input  logic                    wvalid,
    output logic                    wready,

    // AXI-Lite Write Response Channel
    output logic [1:0]              bresp,
    output logic                    bvalid,
    input  logic                    bready,

    // AXI-Lite Read Address Channel
    input  logic [ADDR_WIDTH-1:0]   araddr,
    input  logic                    arvalid,
    output logic                    arready,

    // AXI-Lite Read Data Channel
    output logic [DATA_WIDTH-1:0]   rdata,
    output logic [1:0]              rresp,
    output logic                    rvalid,
    input  logic                    rready,

    // UART serial interface
    output logic                    uart_tx,
    input  logic                    uart_rx,

    // Interrupt output
    output logic                    irq
);

    // ========================================
    // Local Parameters
    // ========================================
    localparam int REG_ADDR_WIDTH = 4;  // 16 registers

    // ========================================
    // Internal Signals - Register Interface
    // ========================================
    logic [REG_ADDR_WIDTH-1:0] reg_addr;
    logic [DATA_WIDTH-1:0]     reg_wdata;
    logic                      reg_wen;
    logic                      reg_ren;
    logic [DATA_WIDTH-1:0]     reg_rdata;
    logic                      reg_error;

    // ========================================
    // Module: axi_lite_slave_if
    // ========================================
    // AXI-Lite protocol to simple register interface conversion
    axi_lite_slave_if #(
        .DATA_WIDTH      (DATA_WIDTH),
        .ADDR_WIDTH      (ADDR_WIDTH),
        .REG_ADDR_WIDTH  (REG_ADDR_WIDTH)
    ) axi_if (
        .clk         (clk),
        .rst_n       (rst_n),
        // AXI-Lite Write Address Channel
        .awaddr      (awaddr),
        .awvalid     (awvalid),
        .awready     (awready),
        // AXI-Lite Write Data Channel
        .wdata       (wdata),
        .wstrb       (wstrb),
        .wvalid      (wvalid),
        .wready      (wready),
        // AXI-Lite Write Response Channel
        .bresp       (bresp),
        .bvalid      (bvalid),
        .bready      (bready),
        // AXI-Lite Read Address Channel
        .araddr      (araddr),
        .arvalid     (arvalid),
        .arready     (arready),
        // AXI-Lite Read Data Channel
        .rdata       (rdata),
        .rresp       (rresp),
        .rvalid      (rvalid),
        .rready      (rready),
        // Register Interface
        .reg_addr    (reg_addr),
        .reg_wdata   (reg_wdata),
        .reg_wen     (reg_wen),
        .reg_ren     (reg_ren),
        .reg_rdata   (reg_rdata),
        .reg_error   (reg_error)
    );

    // ========================================
    // Module: uart_top
    // ========================================
    // Complete UART peripheral (registers + TX/RX paths)
    uart_top #(
        .DATA_WIDTH     (DATA_WIDTH),
        .TX_FIFO_DEPTH  (TX_FIFO_DEPTH),
        .RX_FIFO_DEPTH  (RX_FIFO_DEPTH)
    ) uart_core (
        .uart_clk    (clk),       // Single clock for Phase 5.3
        .rst_n       (rst_n),
        // Register interface from AXI
        .reg_addr    (reg_addr),
        .reg_wdata   (reg_wdata),
        .reg_wen     (reg_wen),
        .reg_ren     (reg_ren),
        .reg_rdata   (reg_rdata),
        .reg_error   (reg_error),
        // UART serial interface
        .uart_tx     (uart_tx),
        .uart_rx     (uart_rx),
        // Interrupt output
        .irq         (irq)
    );

    // ========================================
    // Assertions for Verification
    // ========================================
`ifdef SIMULATION
    initial begin
        // Check parameters
        assert (DATA_WIDTH == 32)
            else $error("uart_axi_top: Only DATA_WIDTH=32 supported");

        assert (ADDR_WIDTH >= REG_ADDR_WIDTH + 2)
            else $error("uart_axi_top: ADDR_WIDTH must be >= REG_ADDR_WIDTH + 2");

        assert (TX_FIFO_DEPTH > 0 && (TX_FIFO_DEPTH & (TX_FIFO_DEPTH - 1)) == 0)
            else $error("uart_axi_top: TX_FIFO_DEPTH must be power of 2");

        assert (RX_FIFO_DEPTH > 0 && (RX_FIFO_DEPTH & (RX_FIFO_DEPTH - 1)) == 0)
            else $error("uart_axi_top: RX_FIFO_DEPTH must be power of 2");
    end

    // Runtime assertions
    always_ff @(posedge clk) begin
        if (rst_n) begin
            // uart_tx should never be X or Z
            assert (!$isunknown(uart_tx))
                else $error("uart_axi_top: uart_tx is X or Z");

            // AXI valid signals should not be X
            assert (!$isunknown(awvalid))
                else $error("uart_axi_top: awvalid is X");
            assert (!$isunknown(wvalid))
                else $error("uart_axi_top: wvalid is X");
            assert (!$isunknown(arvalid))
                else $error("uart_axi_top: arvalid is X");
        end
    end
`endif

endmodule
