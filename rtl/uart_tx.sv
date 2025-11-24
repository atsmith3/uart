/*
 * UART Transmitter Core
 *
 * Serializes and transmits data over UART TX line using 8N1 format:
 *   - 1 start bit (LOW)
 *   - 8 data bits (LSB first)
 *   - 1 stop bit (HIGH)
 *
 * Parameters:
 *   DATA_WIDTH - Data width (default: 8)
 */

module uart_tx #(
    parameter int DATA_WIDTH = 8
) (
    input  logic                    uart_clk,
    input  logic                    rst_n,
    input  logic                    baud_tick,   // 16× baud rate tick (currently just 1× for TX)

    // Data interface
    input  logic [DATA_WIDTH-1:0]   tx_data,
    input  logic                    tx_valid,
    output logic                    tx_ready,

    // Serial output
    output logic                    tx_serial,
    output logic                    tx_active    // Transmission in progress
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
    logic [DATA_WIDTH-1:0] shift_reg;
    logic [3:0] bit_counter;  // Counts 0-9 (start + 8 data + stop)

    // State register
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else if (baud_tick) begin
            state <= next_state;
        end
    end

    // Next state logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (tx_valid) begin
                    next_state = START;
                end
            end
            START: begin
                next_state = DATA;
            end
            DATA: begin
                if (bit_counter == 4'(DATA_WIDTH - 1)) begin
                    next_state = STOP;
                end
            end
            STOP: begin
                next_state = IDLE;
            end
        endcase
    end

    // Shift register and bit counter
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= '0;
            bit_counter <= '0;
        end else if (baud_tick) begin
            case (state)
                IDLE: begin
                    if (tx_valid) begin
                        shift_reg <= tx_data;
                        bit_counter <= '0;
                    end
                end
                START: begin
                    bit_counter <= '0;
                end
                DATA: begin
                    shift_reg <= {1'b0, shift_reg[DATA_WIDTH-1:1]};  // Shift right (LSB first)
                    bit_counter <= bit_counter + 1'b1;
                end
                STOP: begin
                    bit_counter <= '0;
                end
            endcase
        end
    end

    // Output logic
    always_comb begin
        case (state)
            IDLE:  tx_serial = 1'b1;  // Idle high
            START: tx_serial = 1'b0;  // Start bit low
            DATA:  tx_serial = shift_reg[0];  // Data bits LSB first
            STOP:  tx_serial = 1'b1;  // Stop bit high
        endcase
    end

    // Ready and active signals
    assign tx_ready = (state == IDLE) && !tx_valid;
    assign tx_active = (state != IDLE);

endmodule
