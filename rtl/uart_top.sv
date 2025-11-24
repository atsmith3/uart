/*
 * UART Top-Level Module
 *
 * Integrates all UART components with AXI-Lite interface:
 *   - AXI-Lite slave interface
 *   - Register file
 *   - Baud rate generator
 *   - TX path (FIFO + transmitter)
 *   - RX path (FIFO + receiver)
 *
 * Parameters:
 *   DATA_WIDTH    - AXI data width (default: 32)
 *   ADDR_WIDTH    - AXI address width (default: 32)
 *   TX_FIFO_DEPTH - TX FIFO depth (default: 8)
 *   RX_FIFO_DEPTH - RX FIFO depth (default: 8)
 *   UART_CLK_FREQ - UART clock frequency in Hz (default: 7372800)
 */

module uart_top #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32,
    parameter int TX_FIFO_DEPTH = 8,
    parameter int RX_FIFO_DEPTH = 8,
    parameter int UART_CLK_FREQ = 7372800
) (
    // System clocks and reset
    input  logic                    clk,         // AXI-Lite clock (~1 MHz)
    input  logic                    rst_n,       // Active low reset
    input  logic                    uart_clk,    // UART clock (7.3728 MHz)

    // AXI-Lite Slave Interface
    input  logic [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  logic [2:0]              s_axi_awprot,
    input  logic                    s_axi_awvalid,
    output logic                    s_axi_awready,

    input  logic [DATA_WIDTH-1:0]   s_axi_wdata,
    input  logic [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  logic                    s_axi_wvalid,
    output logic                    s_axi_wready,

    output logic [1:0]              s_axi_bresp,
    output logic                    s_axi_bvalid,
    input  logic                    s_axi_bready,

    input  logic [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  logic [2:0]              s_axi_arprot,
    input  logic                    s_axi_arvalid,
    output logic                    s_axi_arready,

    output logic [DATA_WIDTH-1:0]   s_axi_rdata,
    output logic [1:0]              s_axi_rresp,
    output logic                    s_axi_rvalid,
    input  logic                    s_axi_rready,

    // UART Interface
    output logic                    uart_tx,
    input  logic                    uart_rx,

    // Interrupt
    output logic                    irq
);

    //--------------------------------------------------------------------------
    // Internal Signals
    //--------------------------------------------------------------------------

    // Register interface
    logic [3:0]             reg_addr;
    logic [DATA_WIDTH-1:0]  reg_wdata;
    logic [DATA_WIDTH/8-1:0] reg_wstrb;
    logic                   reg_wen;
    logic                   reg_ren;
    logic [DATA_WIDTH-1:0]  reg_rdata;
    logic                   reg_error;

    // Baud rate generator
    logic [7:0]             baud_divisor;
    logic                   baud_enable;
    logic                   baud_tick;

    // TX path
    logic [7:0]             tx_wr_data;
    logic                   tx_wr_en;
    logic                   tx_empty;
    logic                   tx_full;
    logic                   tx_active;
    logic [3:0]             tx_level;
    logic                   tx_fifo_reset;

    // RX path
    logic [7:0]             rx_rd_data;
    logic                   rx_rd_en;
    logic                   rx_empty;
    logic                   rx_full;
    logic                   rx_active;
    logic [3:0]             rx_level;
    logic                   frame_error;
    logic                   overrun_error;
    logic                   rx_fifo_reset;

    // Reset synchronizers for UART clock domain
    logic                   uart_rst_n;

    //--------------------------------------------------------------------------
    // Clock Domain Crossing - Reset Synchronization
    //--------------------------------------------------------------------------

    // Synchronize reset to UART clock domain
    logic [2:0] uart_rst_sync;

    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_rst_sync <= '0;
        end else begin
            uart_rst_sync <= {uart_rst_sync[1:0], 1'b1};
        end
    end

    assign uart_rst_n = uart_rst_sync[2];

    //--------------------------------------------------------------------------
    // AXI-Lite Slave Interface
    //--------------------------------------------------------------------------

    axi_lite_slave_if #(
        .DATA_WIDTH     (DATA_WIDTH),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .REG_ADDR_WIDTH (4)
    ) axi_slave (
        .clk        (clk),
        .rst_n      (rst_n),

        // AXI-Lite interface
        .awaddr     (s_axi_awaddr),
        .awprot     (s_axi_awprot),
        .awvalid    (s_axi_awvalid),
        .awready    (s_axi_awready),
        .wdata      (s_axi_wdata),
        .wstrb      (s_axi_wstrb),
        .wvalid     (s_axi_wvalid),
        .wready     (s_axi_wready),
        .bresp      (s_axi_bresp),
        .bvalid     (s_axi_bvalid),
        .bready     (s_axi_bready),
        .araddr     (s_axi_araddr),
        .arprot     (s_axi_arprot),
        .arvalid    (s_axi_arvalid),
        .arready    (s_axi_arready),
        .rdata      (s_axi_rdata),
        .rresp      (s_axi_rresp),
        .rvalid     (s_axi_rvalid),
        .rready     (s_axi_rready),

        // Register interface
        .reg_addr   (reg_addr),
        .reg_wdata  (reg_wdata),
        .reg_wstrb  (reg_wstrb),
        .reg_wen    (reg_wen),
        .reg_ren    (reg_ren),
        .reg_rdata  (reg_rdata),
        .reg_error  (reg_error)
    );

    //--------------------------------------------------------------------------
    // Register File
    //--------------------------------------------------------------------------

    // Note: Register file runs in AXI clock domain
    // TX/RX interfaces need CDC if clocks are different
    // For this design, we assume system clock and UART clock are asynchronous

    uart_regs #(
        .DATA_WIDTH      (DATA_WIDTH),
        .REG_ADDR_WIDTH  (4)
    ) regs (
        .clk             (clk),
        .rst_n           (rst_n),

        // Register interface
        .reg_addr        (reg_addr),
        .reg_wdata       (reg_wdata),
        .reg_wstrb       (reg_wstrb),
        .reg_wen         (reg_wen),
        .reg_ren         (reg_ren),
        .reg_rdata       (reg_rdata),
        .reg_error       (reg_error),

        // TX path (CDC needed)
        .tx_wr_data      (tx_wr_data),
        .tx_wr_en        (tx_wr_en),
        .tx_empty        (tx_empty),
        .tx_full         (tx_full),
        .tx_active       (tx_active),
        .tx_level        (tx_level),

        // RX path (CDC needed)
        .rx_rd_data      (rx_rd_data),
        .rx_rd_en        (rx_rd_en),
        .rx_empty        (rx_empty),
        .rx_full         (rx_full),
        .rx_active       (rx_active),
        .rx_level        (rx_level),
        .frame_error     (frame_error),
        .overrun_error   (overrun_error),

        // Baud rate generator
        .baud_divisor    (baud_divisor),
        .baud_enable     (baud_enable),

        // FIFO control
        .tx_fifo_reset   (tx_fifo_reset),
        .rx_fifo_reset   (rx_fifo_reset),

        // Interrupt
        .irq             (irq)
    );

    //--------------------------------------------------------------------------
    // Baud Rate Generator
    //--------------------------------------------------------------------------

    uart_baud_gen #(
        .DIVISOR_WIDTH (8)
    ) baud_gen (
        .uart_clk      (uart_clk),
        .rst_n         (uart_rst_n),
        .baud_divisor  (baud_divisor),
        .enable        (baud_enable),
        .baud_tick     (baud_tick)
    );

    //--------------------------------------------------------------------------
    // TX Path
    //--------------------------------------------------------------------------

    uart_tx_path #(
        .FIFO_DEPTH (TX_FIFO_DEPTH),
        .DATA_WIDTH (8)
    ) tx_path (
        .uart_clk      (uart_clk),
        .rst_n         (uart_rst_n),
        .baud_tick     (baud_tick),

        // FIFO write interface (from registers - CDC needed)
        .wr_data       (tx_wr_data),
        .wr_en         (tx_wr_en),

        // Serial output
        .tx_serial     (uart_tx),

        // Status (to registers - CDC needed)
        .tx_empty      (tx_empty),
        .tx_full       (tx_full),
        .tx_active     (tx_active),
        .tx_level      (tx_level),

        // Control
        .fifo_reset    (tx_fifo_reset)
    );

    //--------------------------------------------------------------------------
    // RX Path
    //--------------------------------------------------------------------------

    uart_rx_path #(
        .FIFO_DEPTH (RX_FIFO_DEPTH),
        .DATA_WIDTH (8)
    ) rx_path (
        .uart_clk       (uart_clk),
        .rst_n          (uart_rst_n),
        .sample_tick    (baud_tick),

        // Serial input
        .rx_serial      (uart_rx),

        // FIFO read interface (to registers - CDC needed)
        .rd_data        (rx_rd_data),
        .rd_en          (rx_rd_en),

        // Status (to registers - CDC needed)
        .rx_empty       (rx_empty),
        .rx_full        (rx_full),
        .rx_active      (rx_active),
        .rx_level       (rx_level),
        .frame_error    (frame_error),
        .overrun_error  (overrun_error),

        // Control
        .fifo_reset     (rx_fifo_reset)
    );

    //--------------------------------------------------------------------------
    // Notes on Clock Domain Crossing
    //--------------------------------------------------------------------------

    // WARNING: This design has CDC issues that need to be addressed for production use:
    //
    // 1. Register writes (tx_wr_en, tx_wr_data, tx_fifo_reset, rx_fifo_reset, baud_divisor)
    //    cross from 'clk' domain to 'uart_clk' domain
    //
    // 2. Register reads (tx_empty, tx_full, rx_rd_data, rx_empty, etc.) cross from
    //    'uart_clk' domain to 'clk' domain
    //
    // For a production design, these should use proper CDC techniques:
    //    - Handshake protocols for control signals
    //    - Async FIFOs for data paths
    //    - Gray code synchronizers for counters
    //
    // For this initial implementation, we're assuming that:
    //    - The clock domains are synchronous OR
    //    - The timing is slow enough that metastability is unlikely OR
    //    - This will be addressed in a future revision
    //
    // TODO: Add proper CDC infrastructure

endmodule
