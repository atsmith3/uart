/*
 * Gray Code Synchronizer
 *
 * Safely synchronizes multi-bit values across clock domains by converting
 * to Gray code (where only one bit changes at a time), synchronizing,
 * and converting back to binary.
 *
 * Theory of Operation:
 *   1. Source domain: Convert binary value to Gray code
 *   2. CDC: Synchronize Gray code bits (safe since only 1 bit changes)
 *   3. Dest domain: Convert Gray code back to binary
 *
 * Parameters:
 *   DATA_WIDTH - Width of data bus (default: 8)
 *   STAGES     - Number of synchronizer stages (default: 2, min: 2)
 *
 * Use Cases:
 *   - FIFO level counters
 *   - Multi-bit configuration values that change occasionally
 *   - Baud rate divisor
 *
 * IMPORTANT: Source data should be stable for multiple clock cycles
 * relative to destination clock to ensure clean Gray code transitions.
 */

module gray_sync #(
    parameter int DATA_WIDTH = 8,
    parameter int STAGES = 2
) (
    // Source domain (data_in is in source domain, not synchronized here)
    input  logic [DATA_WIDTH-1:0]   data_in,     // Binary input

    // Destination domain
    input  logic                    clk_dst,
    input  logic                    rst_n_dst,
    output logic [DATA_WIDTH-1:0]   data_out     // Binary output
);

    // Gray code representation of input
    logic [DATA_WIDTH-1:0] gray_in;

    // Synchronized Gray code
    logic [DATA_WIDTH-1:0] gray_sync;

    //--------------------------------------------------------------------------
    // Binary to Gray Code Conversion (Source Domain - Combinational)
    //--------------------------------------------------------------------------

    assign gray_in = data_in ^ (data_in >> 1);

    //--------------------------------------------------------------------------
    // Synchronize Gray Code Bits
    //--------------------------------------------------------------------------

    multi_bit_sync #(
        .DATA_WIDTH (DATA_WIDTH),
        .STAGES     (STAGES)
    ) gray_synchronizer (
        .clk_dst    (clk_dst),
        .rst_n_dst  (rst_n_dst),
        .data_in    (gray_in),
        .data_out   (gray_sync)
    );

    //--------------------------------------------------------------------------
    // Gray to Binary Conversion (Destination Domain - Combinational)
    //--------------------------------------------------------------------------

    always_comb begin
        data_out[DATA_WIDTH-1] = gray_sync[DATA_WIDTH-1];
        for (int i = DATA_WIDTH-2; i >= 0; i--) begin
            data_out[i] = data_out[i+1] ^ gray_sync[i];
        end
    end

    //--------------------------------------------------------------------------
    // Assertions
    //--------------------------------------------------------------------------

    // synthesis translate_off
    initial begin
        assert (STAGES >= 2) else
            $error("gray_sync: STAGES must be at least 2");
    end
    // synthesis translate_on

endmodule
