/*
 * UART Register File
 *
 * Implements control and status registers for UART peripheral.
 *
 * Register Map (byte-addressed, 32-bit aligned):
 *   0x00: CTRL        - Control register (RW)
 *   0x04: STATUS      - Status register (RO)
 *   0x08: TX_DATA     - Transmit data (WO, writes to TX FIFO)
 *   0x0C: RX_DATA     - Receive data (RO, reads from RX FIFO)
 *   0x10: BAUD_DIV    - Baud rate divisor (RW)
 *   0x14: INT_ENABLE  - Interrupt enable (RW)
 *   0x18: INT_STATUS  - Interrupt status, write 1 to clear (RW1C)
 *   0x1C: FIFO_CTRL   - FIFO control (RW, self-clearing bits)
 */

module uart_regs #(
    parameter int DATA_WIDTH = 32,
    parameter int REG_ADDR_WIDTH = 4
) (
    input  logic                        clk,
    input  logic                        rst_n,

    // Register interface from AXI slave
    input  logic [REG_ADDR_WIDTH-1:0]   reg_addr,
    input  logic [DATA_WIDTH-1:0]       reg_wdata,
    input  logic [DATA_WIDTH/8-1:0]     reg_wstrb,
    input  logic                        reg_wen,
    input  logic                        reg_ren,
    output logic [DATA_WIDTH-1:0]       reg_rdata,
    output logic                        reg_error,

    // UART TX path interface
    output logic [7:0]                  tx_wr_data,
    output logic                        tx_wr_en,
    input  logic                        tx_empty,
    input  logic                        tx_full,
    input  logic                        tx_active,
    input  logic [3:0]                  tx_level,

    // UART RX path interface
    input  logic [7:0]                  rx_rd_data,
    output logic                        rx_rd_en,
    input  logic                        rx_empty,
    input  logic                        rx_full,
    input  logic                        rx_active,
    input  logic [3:0]                  rx_level,
    input  logic                        frame_error,
    input  logic                        overrun_error,

    // Baud rate generator
    output logic [7:0]                  baud_divisor,
    output logic                        baud_enable,

    // FIFO control
    output logic                        tx_fifo_reset,
    output logic                        rx_fifo_reset,

    // Interrupt output
    output logic                        irq
);

    // Register addresses
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_CTRL       = 4'h0;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_STATUS     = 4'h1;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_TX_DATA    = 4'h2;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_RX_DATA    = 4'h3;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_BAUD_DIV   = 4'h4;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_INT_ENABLE = 4'h5;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_INT_STATUS = 4'h6;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_FIFO_CTRL  = 4'h7;

    // Control register (0x00)
    logic ctrl_tx_en;
    logic ctrl_rx_en;

    // Status register (0x04) - read-only, reflects actual status
    // [7:0] = status flags, [15:8] = tx_level, [23:16] = rx_level

    // Baud divisor register (0x10)
    logic [7:0] baud_div_reg;

    // Interrupt enable register (0x14)
    logic int_en_tx_ready;
    logic int_en_rx_ready;
    logic int_en_frame_err;
    logic int_en_overrun;

    // Interrupt status register (0x18) - W1C
    logic int_stat_tx_ready;
    logic int_stat_rx_ready;
    logic int_stat_frame_err;
    logic int_stat_overrun;

    // Error flags (sticky, cleared by writing to INT_STATUS)
    logic frame_error_sticky;
    logic overrun_error_sticky;

    //--------------------------------------------------------------------------
    // Register Write Logic
    //--------------------------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_tx_en <= 1'b0;
            ctrl_rx_en <= 1'b0;
            baud_div_reg <= 8'd4;  // Default: 115200 baud (7.3728 MHz / (115200 * 16) = 4)
            int_en_tx_ready <= 1'b0;
            int_en_rx_ready <= 1'b0;
            int_en_frame_err <= 1'b0;
            int_en_overrun <= 1'b0;
            int_stat_tx_ready <= 1'b0;
            int_stat_rx_ready <= 1'b0;
            int_stat_frame_err <= 1'b0;
            int_stat_overrun <= 1'b0;
            frame_error_sticky <= 1'b0;
            overrun_error_sticky <= 1'b0;
            tx_fifo_reset <= 1'b0;
            rx_fifo_reset <= 1'b0;
        end else begin
            // Self-clearing bits
            tx_fifo_reset <= 1'b0;
            rx_fifo_reset <= 1'b0;

            // Update sticky error flags
            if (frame_error) frame_error_sticky <= 1'b1;
            if (overrun_error) overrun_error_sticky <= 1'b1;

            // Update interrupt status bits
            if (!tx_full) int_stat_tx_ready <= 1'b1;
            if (!rx_empty) int_stat_rx_ready <= 1'b1;
            if (frame_error) int_stat_frame_err <= 1'b1;
            if (overrun_error) int_stat_overrun <= 1'b1;

            // Register writes
            if (reg_wen) begin
                case (reg_addr)
                    ADDR_CTRL: begin
                        if (reg_wstrb[0]) begin
                            ctrl_tx_en <= reg_wdata[0];
                            ctrl_rx_en <= reg_wdata[1];
                        end
                    end

                    ADDR_BAUD_DIV: begin
                        if (reg_wstrb[0]) baud_div_reg[7:0] <= reg_wdata[7:0];
                    end

                    ADDR_INT_ENABLE: begin
                        if (reg_wstrb[0]) begin
                            int_en_tx_ready <= reg_wdata[0];
                            int_en_rx_ready <= reg_wdata[1];
                            int_en_frame_err <= reg_wdata[2];
                            int_en_overrun <= reg_wdata[3];
                        end
                    end

                    ADDR_INT_STATUS: begin
                        // Write 1 to clear
                        if (reg_wstrb[0]) begin
                            if (reg_wdata[0]) int_stat_tx_ready <= 1'b0;
                            if (reg_wdata[1]) int_stat_rx_ready <= 1'b0;
                            if (reg_wdata[2]) begin
                                int_stat_frame_err <= 1'b0;
                                frame_error_sticky <= 1'b0;
                            end
                            if (reg_wdata[3]) begin
                                int_stat_overrun <= 1'b0;
                                overrun_error_sticky <= 1'b0;
                            end
                        end
                    end

                    ADDR_FIFO_CTRL: begin
                        if (reg_wstrb[0]) begin
                            tx_fifo_reset <= reg_wdata[0];
                            rx_fifo_reset <= reg_wdata[1];
                        end
                    end

                    default: begin
                        // Other addresses: no action
                    end
                endcase
            end
        end
    end

    //--------------------------------------------------------------------------
    // Register Read Logic
    //--------------------------------------------------------------------------

    always_comb begin
        reg_rdata = '0;
        reg_error = 1'b0;

        if (reg_ren) begin
            case (reg_addr)
                ADDR_CTRL: begin
                    reg_rdata[0] = ctrl_tx_en;
                    reg_rdata[1] = ctrl_rx_en;
                end

                ADDR_STATUS: begin
                    reg_rdata[0] = tx_empty;
                    reg_rdata[1] = tx_full;
                    reg_rdata[2] = rx_empty;
                    reg_rdata[3] = rx_full;
                    reg_rdata[4] = tx_active;
                    reg_rdata[5] = rx_active;
                    reg_rdata[6] = frame_error_sticky;
                    reg_rdata[7] = overrun_error_sticky;
                    reg_rdata[15:8] = {4'b0, tx_level};
                    reg_rdata[23:16] = {4'b0, rx_level};
                end

                ADDR_TX_DATA: begin
                    // Write-only register, reads return 0
                    reg_rdata = '0;
                end

                ADDR_RX_DATA: begin
                    reg_rdata[7:0] = rx_holding_reg;
                end

                ADDR_BAUD_DIV: begin
                    reg_rdata[7:0] = baud_div_reg;
                end

                ADDR_INT_ENABLE: begin
                    reg_rdata[0] = int_en_tx_ready;
                    reg_rdata[1] = int_en_rx_ready;
                    reg_rdata[2] = int_en_frame_err;
                    reg_rdata[3] = int_en_overrun;
                end

                ADDR_INT_STATUS: begin
                    reg_rdata[0] = int_stat_tx_ready;
                    reg_rdata[1] = int_stat_rx_ready;
                    reg_rdata[2] = int_stat_frame_err;
                    reg_rdata[3] = int_stat_overrun;
                end

                ADDR_FIFO_CTRL: begin
                    // Self-clearing bits always read as 0
                    reg_rdata = '0;
                end

                default: begin
                    reg_error = 1'b1;  // Invalid address
                end
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // TX/RX Interface
    //--------------------------------------------------------------------------

    // TX FIFO write (on write to TX_DATA register)
    assign tx_wr_en = reg_wen && (reg_addr == ADDR_TX_DATA) && reg_wstrb[0] && ctrl_tx_en;
    assign tx_wr_data = reg_wdata[7:0];

    // synthesis translate_off
    always @(posedge clk) begin
        if (tx_wr_en) begin
            $display("[uart_regs] %0t: TX_DATA write 0x%h (reg_wen=%b, reg_addr=%h, reg_wstrb=%h, ctrl_tx_en=%b)",
                     $time, reg_wdata[7:0], reg_wen, reg_addr, reg_wstrb, ctrl_tx_en);
        end
    end
    // synthesis translate_on

    // RX FIFO read with prefetch holding register
    // FIFO has registered output: rd_data valid 1 cycle after rd_en
    // Use holding register that prefetches data so it's always ready
    logic [7:0] rx_holding_reg;
    logic rx_holding_valid;
    logic rx_fetch_req;

    // State: IDLE -> FETCHING -> READY
    typedef enum logic [1:0] {
        RX_IDLE     = 2'b00,  // No data available
        RX_FETCHING = 2'b01,  // Requested data from FIFO, waiting 1 cycle
        RX_READY    = 2'b10   // Data in holding register, ready to read
    } rx_state_t;

    rx_state_t rx_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_holding_reg <= '0;
            rx_holding_valid <= 1'b0;
            rx_state <= RX_IDLE;
        end else if (!ctrl_rx_en) begin
            // Reset FSM when RX is disabled
            rx_holding_reg <= '0;
            rx_holding_valid <= 1'b0;
            rx_state <= RX_IDLE;
        end else begin
            case (rx_state)
                RX_IDLE: begin
                    // Start fetch when FIFO has data
                    if (!rx_empty && ctrl_rx_en) begin
                        rx_state <= RX_FETCHING;
                        // synthesis translate_off
                        $display("[uart_regs] %0t: RX_IDLE -> RX_FETCHING (rx_empty=%b)", $time, rx_empty);
                        // synthesis translate_on
                    end
                end

                RX_FETCHING: begin
                    // Capture data after 1-cycle FIFO latency
                    rx_holding_reg <= rx_rd_data;
                    rx_holding_valid <= 1'b1;
                    rx_state <= RX_READY;
                    // synthesis translate_off
                    $display("[uart_regs] %0t: RX_FETCHING -> RX_READY (data=0x%h)", $time, rx_rd_data);
                    // synthesis translate_on
                end

                RX_READY: begin
                    // If register is read, consume holding register
                    if (reg_ren && (reg_addr == ADDR_RX_DATA) && ctrl_rx_en) begin
                        rx_holding_valid <= 1'b0;
                        // synthesis translate_off
                        $display("[uart_regs] %0t: RX_READY consumed (data=0x%h, rx_empty=%b)",
                                 $time, rx_holding_reg, rx_empty);
                        // synthesis translate_on
                        // If more data available, start next fetch immediately
                        if (!rx_empty) begin
                            rx_state <= RX_FETCHING;
                        end else begin
                            rx_state <= RX_IDLE;
                        end
                    end
                    // Handle case where holding register becomes invalid (e.g., during init)
                    // Go back to IDLE if holding register was never validated
                    else if (!rx_holding_valid) begin
                        rx_state <= RX_IDLE;
                    end
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    // Assert rd_en when entering FETCHING state (from either IDLE or READY)
    // Need to check next state transition, not just current state
    logic rx_entering_fetching;
    assign rx_entering_fetching = ((rx_state == RX_IDLE) && !rx_empty && ctrl_rx_en) ||
                                   ((rx_state == RX_READY) && reg_ren && (reg_addr == ADDR_RX_DATA) && ctrl_rx_en && !rx_empty);
    assign rx_rd_en = rx_entering_fetching;

    //--------------------------------------------------------------------------
    // Baud Rate Generator Control
    //--------------------------------------------------------------------------

    assign baud_divisor = baud_div_reg;
    assign baud_enable = ctrl_tx_en || ctrl_rx_en;

    //--------------------------------------------------------------------------
    // Interrupt Generation
    //--------------------------------------------------------------------------

    assign irq = (int_stat_tx_ready && int_en_tx_ready) ||
                 (int_stat_rx_ready && int_en_rx_ready) ||
                 (int_stat_frame_err && int_en_frame_err) ||
                 (int_stat_overrun && int_en_overrun);

endmodule
