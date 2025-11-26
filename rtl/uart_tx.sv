/*
 * UART Transmitter
 *
 * Serializes 8-bit data into UART frame format (8N1).
 * Frame: 1 start bit (0) + 8 data bits (LSB first) + 1 stop bit (1)
 *
 * Features:
 * - 8N1 format (8 data bits, no parity, 1 stop bit)
 * - Ready/valid handshake interface
 * - 16× oversampling (16 baud_ticks per bit period)
 * - LSB-first transmission
 * - Idle line high (mark state)
 *
 * Timing:
 * - Bit period = 16 baud_ticks
 * - Frame time = 160 baud_ticks (10 bits × 16)
 *
 * Usage:
 *   uart_tx tx_inst (
 *       .uart_clk   (uart_clk),
 *       .rst_n      (rst_n),
 *       .baud_tick  (baud_tick_16x),
 *       .tx_data    (data),
 *       .tx_valid   (valid),
 *       .tx_ready   (ready),
 *       .tx_serial  (uart_tx_line),
 *       .tx_active  (transmitting)
 *   );
 *
 * IMPORTANT:
 * - baud_tick must be 16× baud rate (from baud_gen)
 * - tx_data must be stable when tx_valid && tx_ready
 * - Transaction occurs in single cycle when both valid and ready
 *
 * References:
 * - INTERFACE_SPECIFICATIONS.md - Module 4: uart_tx
 */

module uart_tx #(
    parameter int DATA_WIDTH = 8,
    parameter int OVERSAMPLE_RATE = 16
) (
    // Clock and reset
    input  logic                  uart_clk,
    input  logic                  rst_n,

    // Baud rate tick
    input  logic                  baud_tick,

    // Data interface (ready/valid)
    input  logic [DATA_WIDTH-1:0] tx_data,
    input  logic                  tx_valid,
    output logic                  tx_ready,

    // Serial output
    output logic                  tx_serial,
    output logic                  tx_active
);

    // State machine
    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11
    } state_t;

    state_t state, next_state;

    // Internal registers
    logic [DATA_WIDTH-1:0] shift_reg;      // Data shift register
    logic [3:0]            tick_counter;   // Count 0-15 for bit period
    logic [2:0]            bit_counter;    // Count 0-7 for data bits

    // State register
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // Next state logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (tx_valid && tx_ready)
                    next_state = START;
            end

            START: begin
                if (baud_tick && tick_counter == OVERSAMPLE_RATE - 1)
                    next_state = DATA;
            end

            DATA: begin
                if (baud_tick && tick_counter == OVERSAMPLE_RATE - 1 && bit_counter == 7)
                    next_state = STOP;
            end

            STOP: begin
                if (baud_tick && tick_counter == OVERSAMPLE_RATE - 1)
                    next_state = IDLE;
            end
        endcase
    end

    // Tick counter (counts baud_ticks within a bit period)
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_counter <= '0;
        end else begin
            if (state == IDLE) begin
                tick_counter <= '0;
            end else if (baud_tick) begin
                if (tick_counter == OVERSAMPLE_RATE - 1)
                    tick_counter <= '0;
                else
                    tick_counter <= tick_counter + 1'b1;
            end
        end
    end

    // Bit counter (counts data bits 0-7)
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_counter <= '0;
        end else begin
            if (state == DATA && baud_tick && tick_counter == OVERSAMPLE_RATE - 1) begin
                bit_counter <= bit_counter + 1'b1;
            end else if (state != DATA) begin
                bit_counter <= '0;
            end
        end
    end

    // Shift register (load on transaction, shift during DATA state)
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= '0;
        end else begin
            if (state == IDLE && tx_valid && tx_ready) begin
                // Load data on transaction
                shift_reg <= tx_data;
            end else if (state == DATA && baud_tick && tick_counter == OVERSAMPLE_RATE - 1) begin
                // Shift right after each bit transmitted
                shift_reg <= {1'b0, shift_reg[DATA_WIDTH-1:1]};
            end
        end
    end

    // Output logic
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_serial <= 1'b1;  // Idle high
        end else begin
            case (state)
                IDLE:   tx_serial <= 1'b1;  // Idle (mark)
                START:  tx_serial <= 1'b0;  // Start bit (space)
                DATA:   tx_serial <= shift_reg[0];  // Data bits LSB first
                STOP:   tx_serial <= 1'b1;  // Stop bit (mark)
            endcase
        end
    end

    // Ready signal
    assign tx_ready = (state == IDLE);

    // Active signal
    assign tx_active = (state != IDLE);

    // Assertions for verification
`ifdef SIMULATION
    initial begin
        // Check parameters
        assert (DATA_WIDTH == 8)
            else $error("uart_tx: Only DATA_WIDTH=8 supported for 8N1");

        assert (OVERSAMPLE_RATE == 16)
            else $warning("uart_tx: Unusual OVERSAMPLE_RATE=%0d", OVERSAMPLE_RATE);
    end

    // Runtime assertions
    always_ff @(posedge uart_clk) begin
        if (rst_n) begin
            // tick_counter should never exceed OVERSAMPLE_RATE-1
            assert (tick_counter < OVERSAMPLE_RATE)
                else $error("uart_tx: tick_counter=%0d exceeds max", tick_counter);

            // bit_counter should never exceed 7
            assert (bit_counter <= 7)
                else $error("uart_tx: bit_counter=%0d exceeds 7", bit_counter);

            // tx_ready should only be high in IDLE
            assert ((state == IDLE) == tx_ready)
                else $error("uart_tx: tx_ready mismatch with state");

            // tx_active should be low only in IDLE
            assert ((state != IDLE) == tx_active)
                else $error("uart_tx: tx_active mismatch with state");
        end
    end
`endif

endmodule
