/*
 * UART Top-Level Module
 *
 * Integrates all UART components with AXI-Lite interface:
 *   - AXI-Lite slave interface
 *   - Register file
 *   - Baud rate generator
 *   - TX path (async FIFO + transmitter)
 *   - RX path (async FIFO + receiver)
 *   - Clock Domain Crossing (CDC) synchronizers
 *
 * Clock Domains:
 *   - clk:      AXI-Lite interface and register file (~1 MHz)
 *   - uart_clk: UART operations (7.3728 MHz for baud generation)
 *
 * CDC Handling:
 *   - TX/RX data: Async FIFOs with Gray code pointers
 *   - Status signals: Multi-bit/bit synchronizers
 *   - Control signals: Gray sync (baud_divisor) and pulse sync (resets)
 *   - Baud enable: Bit synchronizer
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

    // Baud rate generator (clk domain → uart_clk domain)
    logic [7:0]             baud_divisor;
    logic [7:0]             baud_divisor_sync;
    logic                   baud_enable;
    logic                   baud_enable_sync;
    logic                   baud_tick;

    // TX path (clk domain → uart_clk domain for data)
    logic [7:0]             tx_wr_data;
    logic                   tx_wr_en;
    logic                   tx_empty;          // from async FIFO (clk domain)
    logic                   tx_full;           // from async FIFO (clk domain)
    logic                   tx_active_uart;    // uart_clk domain
    logic                   tx_active;         // synchronized to clk domain
    logic [3:0]             tx_level_uart;     // uart_clk domain
    logic [3:0]             tx_level;          // synchronized to clk domain
    logic                   tx_fifo_reset;

    // RX path (uart_clk domain → clk domain for data)
    logic [7:0]             rx_rd_data;
    logic                   rx_rd_en;
    logic                   rx_empty;          // from async FIFO (clk domain)
    logic                   rx_full_uart;      // uart_clk domain
    logic                   rx_full;           // synchronized to clk domain
    logic                   rx_active_uart;    // uart_clk domain
    logic                   rx_active;         // synchronized to clk domain
    logic [3:0]             rx_level_uart;     // uart_clk domain
    logic [3:0]             rx_level;          // synchronized to clk domain
    logic                   frame_error_uart;  // uart_clk domain
    logic                   frame_error;       // synchronized to clk domain
    logic                   overrun_error_uart;// uart_clk domain
    logic                   overrun_error;     // synchronized to clk domain
    logic                   rx_fifo_reset;

    // Reset synchronizers
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
    // CDC - Control Signals (clk → uart_clk)
    //--------------------------------------------------------------------------

    // Baud divisor: Multi-bit value that changes together → Gray code sync
    gray_sync #(
        .DATA_WIDTH (8),
        .STAGES     (2)
    ) baud_divisor_sync_inst (
        .data_in    (baud_divisor),
        .clk_dst    (uart_clk),
        .rst_n_dst  (uart_rst_n),
        .data_out   (baud_divisor_sync)
    );

    // Baud enable: Single bit → bit synchronizer
    bit_sync #(
        .STAGES (2)
    ) baud_enable_sync_inst (
        .clk_dst    (uart_clk),
        .rst_n_dst  (uart_rst_n),
        .data_in    (baud_enable),
        .data_out   (baud_enable_sync)
    );

    //--------------------------------------------------------------------------
    // CDC - TX Status Signals (uart_clk → clk)
    //--------------------------------------------------------------------------

    // tx_empty and tx_full come directly from async FIFO (already in clk domain)

    // tx_active: Single bit → bit synchronizer
    bit_sync #(
        .STAGES (2)
    ) tx_active_sync_inst (
        .clk_dst    (clk),
        .rst_n_dst  (rst_n),
        .data_in    (tx_active_uart),
        .data_out   (tx_active)
    );

    // tx_level: 4-bit counter → Gray code sync
    gray_sync #(
        .DATA_WIDTH (4),
        .STAGES     (2)
    ) tx_level_sync_inst (
        .data_in    (tx_level_uart),
        .clk_dst    (clk),
        .rst_n_dst  (rst_n),
        .data_out   (tx_level)
    );

    //--------------------------------------------------------------------------
    // CDC - RX Status Signals (uart_clk → clk)
    //--------------------------------------------------------------------------

    // rx_empty comes directly from async FIFO (already in clk domain)

    // rx_full, rx_active, frame_error, overrun_error: Independent bits → multi_bit_sync
    logic [3:0] rx_status_uart;
    logic [3:0] rx_status_sync;

    assign rx_status_uart = {rx_full_uart, rx_active_uart, frame_error_uart, overrun_error_uart};

    multi_bit_sync #(
        .DATA_WIDTH (4),
        .STAGES     (2)
    ) rx_status_sync_inst (
        .clk_dst    (clk),
        .rst_n_dst  (rst_n),
        .data_in    (rx_status_uart),
        .data_out   (rx_status_sync)
    );

    assign {rx_full, rx_active, frame_error, overrun_error} = rx_status_sync;

    // rx_level: 4-bit counter → Gray code sync
    gray_sync #(
        .DATA_WIDTH (4),
        .STAGES     (2)
    ) rx_level_sync_inst (
        .data_in    (rx_level_uart),
        .clk_dst    (clk),
        .rst_n_dst  (rst_n),
        .data_out   (rx_level)
    );

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

        // TX path (synchronized signals)
        .tx_wr_data      (tx_wr_data),
        .tx_wr_en        (tx_wr_en),
        .tx_empty        (tx_empty),
        .tx_full         (tx_full),
        .tx_active       (tx_active),
        .tx_level        (tx_level),

        // RX path (synchronized signals)
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
        .baud_divisor  (baud_divisor_sync),
        .enable        (baud_enable_sync),
        .baud_tick     (baud_tick)
    );

    //--------------------------------------------------------------------------
    // TX Path
    //--------------------------------------------------------------------------

    uart_tx_path #(
        .FIFO_DEPTH (TX_FIFO_DEPTH),
        .DATA_WIDTH (8)
    ) tx_path (
        // Write clock domain (from registers)
        .wr_clk        (clk),
        .wr_rst_n      (rst_n),
        .wr_data       (tx_wr_data),
        .wr_en         (tx_wr_en),
        .wr_full       (tx_full),

        // UART clock domain
        .uart_clk      (uart_clk),
        .uart_rst_n    (uart_rst_n),
        .baud_tick     (baud_tick),

        // Serial output
        .tx_serial     (uart_tx),

        // Status (in uart_clk domain)
        .tx_empty      (tx_empty),
        .tx_active     (tx_active_uart),
        .tx_level      (tx_level_uart),

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
        // UART clock domain
        .uart_clk       (uart_clk),
        .uart_rst_n     (uart_rst_n),
        .sample_tick    (baud_tick),

        // Serial input
        .rx_serial      (uart_rx),

        // Read clock domain (to registers)
        .rd_clk         (clk),
        .rd_rst_n       (rst_n),
        .rd_data        (rx_rd_data),
        .rd_en          (rx_rd_en),
        .rd_empty       (rx_empty),

        // Status (in uart_clk domain)
        .rx_full        (rx_full_uart),
        .rx_active      (rx_active_uart),
        .rx_level       (rx_level_uart),
        .frame_error    (frame_error_uart),
        .overrun_error  (overrun_error_uart),

        // Control
        .fifo_reset     (rx_fifo_reset)
    );

endmodule
