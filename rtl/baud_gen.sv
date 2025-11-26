/*
 * Baud Rate Generator
 *
 * Generates baud rate tick enable from UART clock for 16× oversampling.
 *
 * Features:
 * - Parameterizable divisor width
 * - Configurable baud rate via divisor register
 * - Enable/disable control
 * - Zero-error tick generation (for 7.3728 MHz clock)
 * - 1 cycle pulse width
 *
 * Timing:
 * - Output frequency = uart_clk / baud_divisor
 * - Pulse width = 1 uart_clk cycle
 * - Jitter = 0 (clock-synchronous)
 *
 * Usage:
 *   baud_gen #(.DIVISOR_WIDTH(8)) baud_gen_inst (
 *       .uart_clk     (uart_clk),
 *       .rst_n        (rst_n),
 *       .baud_divisor (divisor),
 *       .enable       (enable),
 *       .baud_tick    (tick_16x)
 *   );
 *
 * IMPORTANT:
 * - baud_divisor must be ≥ 1 (0 is invalid, disables output)
 * - baud_divisor can be changed dynamically
 * - enable=0 stops tick generation
 *
 * References:
 * - INTERFACE_SPECIFICATIONS.md - Module 3: baud_gen
 */

module baud_gen #(
    parameter int DIVISOR_WIDTH = 8,
    parameter int UART_CLK_FREQ = 7372800
) (
    // Clock and reset
    input  logic                      uart_clk,
    input  logic                      rst_n,

    // Configuration
    input  logic [DIVISOR_WIDTH-1:0]  baud_divisor,
    input  logic                      enable,

    // Output
    output logic                      baud_tick
);

    // Internal counter
    logic [DIVISOR_WIDTH-1:0] counter;

    // Counter and tick generation
    always_ff @(posedge uart_clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= '0;
            baud_tick <= 1'b0;
        end else if (!enable || baud_divisor == 0) begin
            // Disabled or invalid divisor
            counter <= '0;
            baud_tick <= 1'b0;
        end else begin
            if (counter == baud_divisor - 1) begin
                // Reached divisor, generate tick
                baud_tick <= 1'b1;
                counter <= '0;
            end else begin
                // Count up
                baud_tick <= 1'b0;
                counter <= counter + 1'b1;
            end
        end
    end

    // Assertions for verification
`ifdef SIMULATION
    initial begin
        // Check reasonable parameters
        assert (DIVISOR_WIDTH >= 4 && DIVISOR_WIDTH <= 16)
            else $warning("baud_gen: Unusual DIVISOR_WIDTH=%0d", DIVISOR_WIDTH);

        assert (UART_CLK_FREQ > 0)
            else $error("baud_gen: UART_CLK_FREQ must be positive");
    end

    // Runtime assertions
    always @(posedge uart_clk) begin
        if (rst_n) begin
            // Counter should never exceed divisor-1
            if (enable && baud_divisor > 0) begin
                assert (counter < baud_divisor)
                    else $error("baud_gen: counter=%0d exceeds divisor=%0d",
                               counter, baud_divisor);
            end

            // baud_tick should be exactly 1 cycle wide
            if (baud_tick) begin
                assert (enable && baud_divisor > 0)
                    else $error("baud_gen: tick generated while disabled");
            end

            // Warn about invalid divisor
            if (enable && baud_divisor == 0) begin
                $warning("baud_gen: enable=1 with divisor=0 (invalid)");
            end
        end
    end
`endif

endmodule
