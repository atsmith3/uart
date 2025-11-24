/*
 * Multi-Bit Synchronizer
 *
 * Synchronizes multiple independent single-bit signals from one clock
 * domain to another. Uses multiple instances of bit synchronizers.
 *
 * IMPORTANT: This is only safe for independent bits where each bit can
 * change independently without correlation. For multi-bit buses where
 * bits change together (like counters), use gray_sync.sv instead.
 *
 * Parameters:
 *   DATA_WIDTH - Number of bits to synchronize (default: 4)
 *   STAGES     - Number of synchronizer stages (default: 2, min: 2)
 *
 * Use Cases:
 *   - Multiple status flags (tx_empty, tx_full, etc.)
 *   - Independent control signals
 *   - NOT for multi-bit counters or buses
 */

module multi_bit_sync #(
    parameter int DATA_WIDTH = 4,
    parameter int STAGES = 2
) (
    input  logic                    clk_dst,
    input  logic                    rst_n_dst,
    input  logic [DATA_WIDTH-1:0]   data_in,
    output logic [DATA_WIDTH-1:0]   data_out
);

    // Generate one synchronizer per bit
    genvar i;
    generate
        for (i = 0; i < DATA_WIDTH; i++) begin : sync_gen
            bit_sync #(
                .STAGES (STAGES)
            ) sync_inst (
                .clk_dst    (clk_dst),
                .rst_n_dst  (rst_n_dst),
                .data_in    (data_in[i]),
                .data_out   (data_out[i])
            );
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Assertions
    //--------------------------------------------------------------------------

    // synthesis translate_off
    initial begin
        assert (STAGES >= 2) else
            $error("multi_bit_sync: STAGES must be at least 2");
    end
    // synthesis translate_on

endmodule
