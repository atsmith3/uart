/*
 * UART Baud Rate Generator
 *
 * Generates baud rate tick (16× oversampling) from UART clock using
 * a simple down-counter divider.
 *
 * For 7.3728 MHz clock:
 *   460800 baud: divisor = 1
 *   115200 baud: divisor = 4
 *   9600 baud:   divisor = 48
 *
 * Parameters:
 *   DIVISOR_WIDTH - Width of divisor register (default: 8, range 1-255)
 */

module uart_baud_gen #(
    parameter int DIVISOR_WIDTH = 8
) (
    input  logic                        uart_clk,
    input  logic                        rst_n,
    input  logic [DIVISOR_WIDTH-1:0]    baud_divisor,  // Divisor value (1-255)
    input  logic                        enable,         // Enable baud generation
    output logic                        baud_tick       // Output tick (1 cycle pulse)
);

    logic [DIVISOR_WIDTH-1:0] counter;

    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= '0;
            baud_tick <= 1'b0;
        end else if (!enable) begin
            counter <= baud_divisor;
            baud_tick <= 1'b0;
        end else if (counter == 0 || counter == 1) begin
            // Generate tick and reload counter
            counter <= baud_divisor;
            baud_tick <= 1'b1;
        end else begin
            counter <= counter - 1'b1;
            baud_tick <= 1'b0;
        end
    end

    // Assertions
    always_ff @(posedge uart_clk) begin
        if (rst_n && enable) begin
            if (baud_divisor == 0) begin
                $error("uart_baud_gen: baud_divisor must be >= 1");
            end
        end
    end

endmodule
