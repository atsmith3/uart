/*
 * UART Receiver
 *
 * Deserializes UART frame format (8N1) with 16× oversampling.
 * Frame: 1 start bit (0) + 8 data bits (LSB first) + 1 stop bit (1)
 *
 * Features:
 * - 8N1 format (8 data bits, no parity, 1 stop bit)
 * - 16× oversampling for noise immunity
 * - Bit-center sampling (sample at count 8 of 16)
 * - Start bit validation (false start detection)
 * - Stop bit validation (frame error detection)
 * - Ready/valid handshake interface
 *
 * Timing:
 * - Bit period = 16 sample_ticks
 * - Frame time = 160 sample_ticks (10 bits × 16)
 * - Sample point = count 8 (middle of bit)
 *
 * Usage:
 *   uart_rx rx_inst (
 *       .uart_clk        (uart_clk),
 *       .rst_n           (rst_n),
 *       .sample_tick     (sample_tick_16x),
 *       .rx_serial_sync  (rx_synchronized),
 *       .rx_data         (data_out),
 *       .rx_valid        (valid),
 *       .rx_ready        (ready_in),
 *       .frame_error     (error),
 *       .rx_active       (receiving)
 *   );
 *
 * IMPORTANT:
 * - rx_serial_sync must be synchronized (use bit_sync)
 * - sample_tick must be 16× baud rate
 * - Sample at middle of bit (count 8) for noise immunity
 *
 * References:
 * - INTERFACE_SPECIFICATIONS.md - Module 5: uart_rx
 */

module uart_rx #(
    parameter int DATA_WIDTH = 8,
    parameter int OVERSAMPLE_RATE = 16
) (
    // Clock and reset
    input  logic                  uart_clk,
    input  logic                  rst_n,

    // Sample rate tick
    input  logic                  sample_tick,

    // Serial input (synchronized!)
    input  logic                  rx_serial_sync,

    // Data interface (ready/valid)
    output logic [DATA_WIDTH-1:0] rx_data,
    output logic                  rx_valid,
    input  logic                  rx_ready,

    // Status
    output logic                  frame_error,
    output logic                  rx_active
);

    // State machine
    typedef enum logic [2:0] {
        IDLE      = 3'b000,
        START_BIT = 3'b001,
        DATA_BITS = 3'b010,
        STOP_BIT  = 3'b011,
        WAIT_ACK  = 3'b100
    } state_t;

    state_t state, next_state;

    // Internal registers
    logic [DATA_WIDTH-1:0] shift_reg;      // Data shift register
    logic [3:0]            sample_counter; // Count 0-15 within bit period
    logic [2:0]            bit_counter;    // Count 0-7 for data bits
    logic                  frame_error_reg;

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
                // Detect start bit (falling edge: 1 → 0)
                if (!rx_serial_sync)
                    next_state = START_BIT;
            end

            START_BIT: begin
                if (sample_tick) begin
                    if (sample_counter == 8) begin
                        // Sample at middle of start bit
                        if (rx_serial_sync == 1'b1) begin
                            // False start - line went back high
                            next_state = IDLE;
                        end
                        // Valid start bit - continue
                    end else if (sample_counter == 15) begin
                        // End of start bit period
                        next_state = DATA_BITS;
                    end
                end
            end

            DATA_BITS: begin
                if (sample_tick && sample_counter == 15) begin
                    if (bit_counter == 7)
                        next_state = STOP_BIT;
                end
            end

            STOP_BIT: begin
                if (sample_tick && sample_counter == 15) begin
                    next_state = WAIT_ACK;
                end
            end

            WAIT_ACK: begin
                if (rx_valid && rx_ready)
                    next_state = IDLE;
            end
        endcase
    end

    // Sample counter (counts 0-15 within each bit period)
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_counter <= '0;
        end else begin
            if (state == IDLE) begin
                sample_counter <= '0;
            end else if (sample_tick) begin
                if (sample_counter == 15)
                    sample_counter <= '0;
                else
                    sample_counter <= sample_counter + 1'b1;
            end
        end
    end

    // Bit counter (counts data bits 0-7)
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_counter <= '0;
        end else begin
            if (state == DATA_BITS && sample_tick && sample_counter == 15) begin
                bit_counter <= bit_counter + 1'b1;
            end else if (state != DATA_BITS) begin
                bit_counter <= '0;
            end
        end
    end

    // Shift register (sample at bit center, shift right for LSB first)
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= '0;
        end else begin
            if (state == DATA_BITS && sample_tick && sample_counter == 8) begin
                // Sample at middle of bit period, shift right (LSB first)
                shift_reg <= {rx_serial_sync, shift_reg[DATA_WIDTH-1:1]};
            end
        end
    end

    // Output data register
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_data <= '0;
        end else begin
            if (state == STOP_BIT && sample_tick && sample_counter == 8) begin
                // Latch data at stop bit sample point
                rx_data <= shift_reg;
            end
        end
    end

    // Frame error detection (stop bit should be high)
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_error_reg <= 1'b0;
        end else begin
            if (state == STOP_BIT && sample_tick && sample_counter == 8) begin
                // Check stop bit at middle of bit period
                if (rx_serial_sync != 1'b1)
                    frame_error_reg <= 1'b1;
            end else if (state == IDLE) begin
                // Clear frame error when idle
                frame_error_reg <= 1'b0;
            end
        end
    end

    // rx_valid generation
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_valid <= 1'b0;
        end else begin
            if (state == STOP_BIT && sample_tick && sample_counter == 15) begin
                // Assert valid at end of stop bit
                rx_valid <= 1'b1;
            end else if (rx_valid && rx_ready) begin
                // Deassert after handshake
                rx_valid <= 1'b0;
            end
        end
    end

    // Status outputs
    assign rx_active = (state != IDLE);
    assign frame_error = frame_error_reg;

    // Assertions for verification
`ifdef SIMULATION
    initial begin
        // Check parameters
        assert (DATA_WIDTH == 8)
            else $error("uart_rx: Only DATA_WIDTH=8 supported for 8N1");

        assert (OVERSAMPLE_RATE == 16)
            else $warning("uart_rx: Unusual OVERSAMPLE_RATE=%0d", OVERSAMPLE_RATE);
    end

    // Runtime assertions
    always_ff @(posedge uart_clk) begin
        if (rst_n) begin
            // sample_counter should never exceed 15
            assert (sample_counter <= 15)
                else $error("uart_rx: sample_counter=%0d exceeds 15", sample_counter);

            // bit_counter should never exceed 7
            assert (bit_counter <= 7)
                else $error("uart_rx: bit_counter=%0d exceeds 7", bit_counter);

            // rx_active should be low only in IDLE
            assert ((state != IDLE) == rx_active)
                else $error("uart_rx: rx_active mismatch with state");
        end
    end
`endif

endmodule
