/*
 * Single-Bit Clock Domain Crossing Synchronizer
 *
 * Synchronizes a single asynchronous bit to the destination clock domain
 * using a 2-stage (or configurable N-stage) flip-flop chain.
 *
 * Features:
 * - Configurable synchronization stages (default: 2)
 * - Metastability protection via multi-stage FFs
 * - MTBF > 10^9 years for 2 stages at typical frequencies
 *
 * Usage:
 *   bit_sync sync_rx (
 *       .clk_dst    (uart_clk),
 *       .rst_n_dst  (rst_n),
 *       .data_in    (uart_rx_pin),
 *       .data_out   (uart_rx_sync)
 *   );
 *
 * IMPORTANT:
 * - Use ONLY for single-bit signals
 * - Do NOT use for multi-bit buses (use Gray code or handshake instead)
 * - Input pulses must be at least 2× destination clock period
 * - Adds 2-3 cycle latency (depending on STAGES parameter)
 *
 * References:
 * - INTERFACE_SPECIFICATIONS.md - Module 1: bit_sync
 * - Clifford E. Cummings, "Clock Domain Crossing (CDC) Design & Verification"
 */

module bit_sync #(
    parameter int  STAGES      = 2,   // Number of synchronization stages (2 or 3)
    parameter logic RESET_VALUE = 1'b0 // Reset value for sync chain (0 or 1)
) (
    // Destination clock domain
    input  logic clk_dst,
    input  logic rst_n_dst,

    // Asynchronous input
    input  logic data_in,

    // Synchronized output
    output logic data_out
);

    // Synthesis attributes for CDC paths
    (* ASYNC_REG = "TRUE" *) logic [STAGES-1:0] sync_chain;

    // Synchronization flip-flop chain
    always_ff @(posedge clk_dst or negedge rst_n_dst) begin
        if (!rst_n_dst) begin
            // Reset to specified value (replicated across all stages)
            sync_chain <= {STAGES{RESET_VALUE}};
        end else begin
            // Shift through synchronization stages
            sync_chain <= {sync_chain[STAGES-2:0], data_in};
        end
    end

    // Output is the last stage
    assign data_out = sync_chain[STAGES-1];

    // Assertions for verification
`ifdef SIMULATION
    initial begin
        assert (STAGES >= 2 && STAGES <= 3)
            else $error("bit_sync: STAGES must be 2 or 3, got %0d", STAGES);
    end
`endif

endmodule
