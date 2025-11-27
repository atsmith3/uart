/*
 * UART Register File
 *
 * Implements control, status, and data registers for UART peripheral.
 * Connects register interface to UART TX/RX paths with proper side effects.
 *
 * Register Map (byte-addressed, 32-bit aligned):
 *   0x00: CTRL        - Control register (TX_EN, RX_EN)
 *   0x04: STATUS      - Status register (RO, reflects hardware state)
 *   0x08: TX_DATA     - Transmit data (WO, pushes to TX FIFO)
 *   0x0C: RX_DATA     - Receive data (RO, pops from RX FIFO)
 *   0x10: BAUD_DIV    - Baud rate divisor
 *   0x14: INT_ENABLE  - Interrupt enable
 *   0x18: INT_STATUS  - Interrupt status (W1C)
 *   0x1C: FIFO_CTRL   - FIFO control (self-clearing)
 *
 * Features:
 * - Register read/write with proper access control (RW/RO/WO)
 * - TX_DATA write → automatic FIFO push
 * - RX_DATA read → automatic FIFO pop (with prefetch)
 * - W1C (Write-1-to-Clear) for INT_STATUS
 * - Self-clearing bits in FIFO_CTRL
 * - Interrupt generation based on enable and status
 * - Error flag management (sticky, clear via INT_STATUS)
 *
 * Critical Implementation:
 * - RX prefetch logic handles FIFO 1-cycle read latency
 * - Reserved bits read as 0, writes ignored
 * - Baud enable when TX_EN or RX_EN set
 *
 * References:
 * - INTERFACE_SPECIFICATIONS.md - Module 9: uart_regs
 */

module uart_regs #(
    parameter int DATA_WIDTH = 32,
    parameter int FIFO_ADDR_WIDTH = 3  // For 8-deep FIFOs
) (
    // Clock and reset
    input  logic                    uart_clk,
    input  logic                    rst_n,

    // Register interface
    input  logic [3:0]              reg_addr,      // Word address (byte addr >> 2)
    input  logic [DATA_WIDTH-1:0]   reg_wdata,
    input  logic                    reg_wen,
    input  logic                    reg_ren,
    output logic [DATA_WIDTH-1:0]   reg_rdata,
    output logic                    reg_error,

    // TX path interface
    output logic [7:0]              wr_data,
    output logic                    wr_en,
    input  logic                    tx_empty,
    input  logic                    tx_full,
    input  logic                    tx_active,
    input  logic [FIFO_ADDR_WIDTH:0] tx_level,

    // RX path interface
    input  logic [7:0]              rx_data,
    output logic                    rd_en,
    input  logic                    rx_empty,
    input  logic                    rx_full,
    input  logic                    rx_active,
    input  logic [FIFO_ADDR_WIDTH:0] rx_level,
    input  logic                    frame_error,
    input  logic                    overrun_error,

    // Baud generator interface
    output logic [15:0]             baud_divisor,
    output logic                    baud_enable,

    // FIFO control
    output logic                    tx_fifo_rst,
    output logic                    rx_fifo_rst,

    // Interrupt output
    output logic                    irq
);

    // Register addresses (word-addressed)
    localparam logic [3:0] ADDR_CTRL       = 4'h0;
    localparam logic [3:0] ADDR_STATUS     = 4'h1;
    localparam logic [3:0] ADDR_TX_DATA    = 4'h2;
    localparam logic [3:0] ADDR_RX_DATA    = 4'h3;
    localparam logic [3:0] ADDR_BAUD_DIV   = 4'h4;
    localparam logic [3:0] ADDR_INT_ENABLE = 4'h5;
    localparam logic [3:0] ADDR_INT_STATUS = 4'h6;
    localparam logic [3:0] ADDR_FIFO_CTRL  = 4'h7;

    // Registers
    logic [1:0]  ctrl_reg;          // [1:0] = {RX_EN, TX_EN}
    logic [15:0] baud_div_reg;
    logic [3:0]  int_enable_reg;
    logic [3:0]  int_status_reg;

    // Internal signals
    logic        reg_write;
    logic        reg_read;
    logic [7:0]  rx_holding_reg;
    logic        rx_data_valid;
    logic        frame_error_sticky;
    logic        overrun_error_sticky;

    // RX prefetch state machine
    typedef enum logic [1:0] {
        RX_IDLE,
        RX_FETCHING,
        RX_READY
    } rx_state_t;
    rx_state_t rx_state;

    // Decode register accesses
    assign reg_write = reg_wen;
    assign reg_read = reg_ren;

    // ========================================
    // CTRL Register (0x00) - RW
    // ========================================
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_reg <= 2'b00;
        end else if (reg_write && reg_addr == ADDR_CTRL) begin
            ctrl_reg <= reg_wdata[1:0];
        end
    end

    // ========================================
    // BAUD_DIV Register (0x10) - RW
    // ========================================
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_div_reg <= 16'h0004;  // Default 115200
        end else if (reg_write && reg_addr == ADDR_BAUD_DIV) begin
            baud_div_reg <= reg_wdata[15:0];
        end
    end

    assign baud_divisor = baud_div_reg;
    assign baud_enable = (ctrl_reg[0] || ctrl_reg[1]);  // TX_EN or RX_EN

    // ========================================
    // INT_ENABLE Register (0x14) - RW
    // ========================================
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            int_enable_reg <= 4'h0;
        end else if (reg_write && reg_addr == ADDR_INT_ENABLE) begin
            int_enable_reg <= reg_wdata[3:0];
        end
    end

    // ========================================
    // INT_STATUS Register (0x18) - RW1C
    // ========================================
    // Interrupt sources:
    // [0] TX_READY   - TX FIFO not full
    // [1] RX_READY   - RX FIFO not empty
    // [2] FRAME_ERR  - Frame error detected
    // [3] OVERRUN    - Overrun error detected

    logic tx_ready_event, rx_ready_event;
    assign tx_ready_event = !tx_full && ctrl_reg[0];   // TX enabled and not full
    assign rx_ready_event = !rx_empty && ctrl_reg[1];  // RX enabled and not empty

    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            int_status_reg <= 4'h0;
        end else begin
            // Set bits on events
            if (tx_ready_event) int_status_reg[0] <= 1'b1;
            if (rx_ready_event) int_status_reg[1] <= 1'b1;
            if (frame_error) int_status_reg[2] <= 1'b1;
            if (overrun_error) int_status_reg[3] <= 1'b1;

            // Clear bits on W1C
            if (reg_write && reg_addr == ADDR_INT_STATUS) begin
                int_status_reg <= int_status_reg & ~reg_wdata[3:0];
            end
        end
    end

    // Generate IRQ output
    assign irq = |(int_status_reg & int_enable_reg);

    // ========================================
    // Sticky Error Flags
    // ========================================
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_error_sticky <= 1'b0;
            overrun_error_sticky <= 1'b0;
        end else begin
            // Set on error
            if (frame_error) frame_error_sticky <= 1'b1;
            if (overrun_error) overrun_error_sticky <= 1'b1;

            // Clear via INT_STATUS W1C
            if (reg_write && reg_addr == ADDR_INT_STATUS) begin
                if (reg_wdata[2]) frame_error_sticky <= 1'b0;
                if (reg_wdata[3]) overrun_error_sticky <= 1'b0;
            end
        end
    end

    // ========================================
    // TX_DATA Register (0x08) - WO
    // ========================================
    // Write side effect: push to TX FIFO
    assign wr_en = reg_write && (reg_addr == ADDR_TX_DATA) && !tx_full;
    assign wr_data = reg_wdata[7:0];

    // ========================================
    // RX_DATA Register (0x0C) - RO
    // ========================================
    // Read side effect: pop from RX FIFO (with prefetch)
    // Prefetch FSM to handle FIFO 1-cycle read latency

    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state <= RX_IDLE;
            rx_holding_reg <= 8'h00;
            rx_data_valid <= 1'b0;
        end else begin
            case (rx_state)
                RX_IDLE: begin
                    if (!rx_empty) begin
                        // Data available, start fetch
                        rx_state <= RX_FETCHING;
                        rx_data_valid <= 1'b0;
                    end
                end

                RX_FETCHING: begin
                    // Wait one cycle for FIFO read latency
                    rx_holding_reg <= rx_data;
                    rx_data_valid <= 1'b1;
                    rx_state <= RX_READY;
                end

                RX_READY: begin
                    if (reg_read && reg_addr == ADDR_RX_DATA) begin
                        // Data consumed, check if more available
                        if (!rx_empty) begin
                            rx_state <= RX_FETCHING;
                            rx_data_valid <= 1'b0;
                        end else begin
                            rx_state <= RX_IDLE;
                            rx_data_valid <= 1'b0;
                        end
                    end
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    // Generate rd_en for RX FIFO
    assign rd_en = (rx_state == RX_IDLE && !rx_empty) ||  // Initial fetch
                   (rx_state == RX_READY && reg_read && reg_addr == ADDR_RX_DATA && !rx_empty);  // Refetch

    // ========================================
    // FIFO_CTRL Register (0x1C) - Self-clearing
    // ========================================
    logic [1:0] fifo_ctrl_reg;

    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_ctrl_reg <= 2'b00;
        end else begin
            if (reg_write && reg_addr == ADDR_FIFO_CTRL) begin
                fifo_ctrl_reg <= reg_wdata[1:0];
            end else begin
                // Self-clear after one cycle
                fifo_ctrl_reg <= 2'b00;
            end
        end
    end

    assign tx_fifo_rst = fifo_ctrl_reg[0];
    assign rx_fifo_rst = fifo_ctrl_reg[1];

    // ========================================
    // STATUS Register (0x04) - RO
    // ========================================
    logic [DATA_WIDTH-1:0] status_value;

    assign status_value = {
        8'h00,                          // [31:24] Reserved
        rx_level[7:0],                  // [23:16] RX FIFO level
        tx_level[7:0],                  // [15:8]  TX FIFO level
        overrun_error_sticky,           // [7]     Overrun error
        frame_error_sticky,             // [6]     Frame error
        rx_active,                      // [5]     RX active
        tx_active,                      // [4]     TX active
        rx_full,                        // [3]     RX FIFO full
        rx_empty,                       // [2]     RX FIFO empty
        tx_full,                        // [1]     TX FIFO full
        tx_empty                        // [0]     TX FIFO empty
    };

    // ========================================
    // Register Read Mux
    // ========================================
    // Combinational read for same-cycle availability (required by AXI-Lite interface)
    always_comb begin
        case (reg_addr)
            ADDR_CTRL:       reg_rdata = {30'h0, ctrl_reg};
            ADDR_STATUS:     reg_rdata = status_value;
            ADDR_TX_DATA:    reg_rdata = 32'h0;  // Write-only
            ADDR_RX_DATA:    reg_rdata = {24'h0, rx_holding_reg};
            ADDR_BAUD_DIV:   reg_rdata = {16'h0, baud_div_reg};
            ADDR_INT_ENABLE: reg_rdata = {28'h0, int_enable_reg};
            ADDR_INT_STATUS: reg_rdata = {28'h0, int_status_reg};
            ADDR_FIFO_CTRL:  reg_rdata = {30'h0, fifo_ctrl_reg};
            default:         reg_rdata = 32'h0;
        endcase
    end

    // Error signal (unused, reserved for future)
    assign reg_error = 1'b0;

    // ========================================
    // Assertions for Verification
    // ========================================
`ifdef SIMULATION
    initial begin
        // Check parameters
        assert (DATA_WIDTH == 32)
            else $error("uart_regs: Only DATA_WIDTH=32 supported");

        assert (FIFO_ADDR_WIDTH >= 3)
            else $warning("uart_regs: FIFO_ADDR_WIDTH < 3 may cause level truncation");
    end

    // Runtime assertions
    always_ff @(posedge uart_clk) begin
        if (rst_n) begin
            // Should never write to TX FIFO when full
            assert (!(wr_en && tx_full))
                else $error("uart_regs: TX FIFO write when full");

            // Should never read from RX FIFO when empty
            assert (!(rd_en && rx_empty))
                else $error("uart_regs: RX FIFO read when empty");

            // CTRL register should only have 2 bits
            assert (ctrl_reg <= 2'b11)
                else $error("uart_regs: ctrl_reg out of range");
        end
    end
`endif

endmodule
