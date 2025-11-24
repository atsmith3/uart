/*
 * Bit Synchronizer
 *
 * Safely synchronizes single-bit signals across clock domains using
 * a multi-stage synchronizer chain to reduce metastability.
 *
 * Parameters:
 *   STAGES - Number of synchronizer stages (default: 2, minimum: 2)
 *
 * Typical MTBF for 2-stage synchronizer is > 10^9 years
 */

module bit_sync #(
    parameter int STAGES = 2  // Number of synchronizer flip-flop stages
) (
    input  logic clk_dst,    // Destination clock domain
    input  logic rst_n_dst,  // Destination domain reset (active low)
    input  logic data_in,    // Asynchronous input
    output logic data_out    // Synchronized output
);

    // Synchronizer chain
    (* ASYNC_REG = "TRUE" *) logic [STAGES-1:0] sync_chain;

    always_ff @(posedge clk_dst or negedge rst_n_dst) begin
        if (!rst_n_dst) begin
            sync_chain <= '0;
        end else begin
            sync_chain <= {sync_chain[STAGES-2:0], data_in};
        end
    end

    // Output is the last stage
    assign data_out = sync_chain[STAGES-1];

    // Assertions for parameter validation
    initial begin
        if (STAGES < 2) begin
            $error("bit_sync: STAGES must be >= 2 for proper metastability protection");
        end
    end

endmodule
