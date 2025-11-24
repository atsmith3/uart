/*
 * UART Receiver Core
 *
 * Deserializes and receives data from UART RX line using 8N1 format with
 * 16× oversampling for noise immunity.
 *
 * Frame format:
 *   - 1 start bit (LOW)
 *   - 8 data bits (LSB first)
 *   - 1 stop bit (HIGH)
 *
 * Sampling strategy:
 *   - 16× oversampling
 *   - Sample at middle of bit period (8th tick out of 16)
 *
 * Parameters:
 *   DATA_WIDTH      - Data width (default: 8)
 *   OVERSAMPLE_RATE - Oversampling rate (default: 16)
 */

module uart_rx #(
    parameter int DATA_WIDTH = 8,
    parameter int OVERSAMPLE_RATE = 16
) (
    input  logic                    uart_clk,
    input  logic                    rst_n,
    input  logic                    sample_tick,  // 16× baud rate tick

    // Serial input (already synchronized)
    input  logic                    rx_serial_sync,

    // Data interface
    output logic [DATA_WIDTH-1:0]   rx_data,
    output logic                    rx_valid,
    input  logic                    rx_ready,

    // Status
    output logic                    frame_error,
    output logic                    rx_active
);

    // State machine
    typedef enum logic [2:0] {
        IDLE      = 3'b000,
        START_BIT = 3'b001,
        DATA_BITS = 3'b010,
        STOP_BIT  = 3'b011
    } state_t;

    state_t state, next_state;

    // Internal registers
    logic [DATA_WIDTH-1:0] shift_reg;
    logic [3:0] bit_counter;      // Counts data bits (0-7)
    logic [4:0] sample_counter;   // Counts samples (0-15)
    logic       frame_error_reg;

    // Detect falling edge for start bit
    logic rx_serial_d;
    logic start_detected;

    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_serial_d <= 1'b1;
        end else if (sample_tick) begin
            rx_serial_d <= rx_serial_sync;
        end
    end

    assign start_detected = rx_serial_d && !rx_serial_sync;

    // State register
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else if (sample_tick) begin
            state <= next_state;
        end
    end

    // Next state logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start_detected) begin
                    next_state = START_BIT;
                end
            end
            START_BIT: begin
                if (sample_counter == 5'(OVERSAMPLE_RATE - 1)) begin
                    // Validate start bit at end of period
                    if (rx_serial_sync == 1'b0) begin
                        next_state = DATA_BITS;
                    end else begin
                        // False start
                        next_state = IDLE;
                    end
                end
            end
            DATA_BITS: begin
                if (sample_counter == 5'(OVERSAMPLE_RATE - 1) && bit_counter == 4'(DATA_WIDTH - 1)) begin
                    next_state = STOP_BIT;
                end
            end
            STOP_BIT: begin
                if (sample_counter == 5'(OVERSAMPLE_RATE - 1)) begin
                    next_state = IDLE;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    // Sample counter
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_counter <= '0;
        end else if (sample_tick) begin
            case (state)
                IDLE: begin
                    if (start_detected) begin
                        sample_counter <= '0;
                    end
                end
                START_BIT, DATA_BITS, STOP_BIT: begin
                    if (sample_counter == 5'(OVERSAMPLE_RATE - 1)) begin
                        sample_counter <= '0;
                    end else begin
                        sample_counter <= sample_counter + 1'b1;
                    end
                end
                default: begin
                    // Do nothing
                end
            endcase
        end
    end

    // Bit counter and shift register
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= '0;
            bit_counter <= '0;
        end else if (sample_tick) begin
            case (state)
                IDLE: begin
                    bit_counter <= '0;
                end
                DATA_BITS: begin
                    // Sample at middle of bit period (sample 8 of 16)
                    if (sample_counter == 5'(OVERSAMPLE_RATE / 2)) begin
                        shift_reg <= {rx_serial_sync, shift_reg[DATA_WIDTH-1:1]};  // Shift right, LSB first
                    end
                    if (sample_counter == 5'(OVERSAMPLE_RATE - 1)) begin
                        bit_counter <= bit_counter + 1'b1;
                    end
                end
                default: begin
                    // Do nothing
                end
            endcase
        end
    end

    // Output data and valid
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_data <= '0;
            rx_valid <= 1'b0;
        end else if (sample_tick) begin
            if (state == STOP_BIT && sample_counter == 5'(OVERSAMPLE_RATE / 2)) begin
                // Sample stop bit and check validity
                if (rx_serial_sync == 1'b1) begin
                    rx_data <= shift_reg;
                    rx_valid <= 1'b1;
                end
            end else if (rx_valid && rx_ready) begin
                rx_valid <= 1'b0;
            end
        end
    end

    // Frame error detection
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_error_reg <= 1'b0;
        end else if (sample_tick) begin
            if (state == STOP_BIT && sample_counter == 5'(OVERSAMPLE_RATE / 2)) begin
                // Frame error if stop bit is not HIGH
                frame_error_reg <= (rx_serial_sync != 1'b1);
            end
        end
    end

    assign frame_error = frame_error_reg;
    assign rx_active = (state != IDLE);

endmodule
