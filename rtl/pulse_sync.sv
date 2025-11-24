/*
 * Pulse Synchronizer with Toggle-Based CDC
 *
 * Safely transfers a pulse from one clock domain to another using a
 * toggle-based handshaking mechanism. Guarantees exactly one pulse
 * in the destination domain for each pulse in the source domain.
 *
 * Theory of Operation:
 *   1. Source: pulse_in causes toggle of src_toggle
 *   2. CDC: Synchronize src_toggle to dst domain
 *   3. Dest: Detect edge on synchronized toggle → generate pulse_out
 *   4. Optional: Synchronize dst_toggle back to src for acknowledgment
 *
 * Parameters:
 *   USE_ACK - Enable acknowledgment path (default: 0)
 *
 * Timing:
 *   - Latency: 2-3 destination clock cycles
 *   - Max pulse rate: Limited by round-trip synchronization time
 *   - Source must not pulse again until ack received (if USE_ACK=1)
 *
 * Use Cases:
 *   - FIFO reset signals
 *   - Interrupt pulses
 *   - Control pulses between clock domains
 */

module pulse_sync #(
    parameter int USE_ACK = 0  // Set to 1 to enable acknowledgment
) (
    // Source clock domain
    input  logic clk_src,
    input  logic rst_n_src,
    input  logic pulse_in,
    output logic ack_out,      // Valid only if USE_ACK=1

    // Destination clock domain
    input  logic clk_dst,
    input  logic rst_n_dst,
    output logic pulse_out
);

    // Source domain toggle register
    logic src_toggle;

    // Synchronized toggle in destination domain
    logic src_toggle_sync1;
    logic src_toggle_sync2;
    logic src_toggle_sync3;  // Extra stage for edge detection

    // Destination domain toggle (for acknowledgment)
    logic dst_toggle;

    // Synchronized ack toggle in source domain
    logic dst_toggle_sync1;
    logic dst_toggle_sync2;

    //--------------------------------------------------------------------------
    // Source Domain Logic
    //--------------------------------------------------------------------------

    // Toggle on pulse input
    always_ff @(posedge clk_src or negedge rst_n_src) begin
        if (!rst_n_src) begin
            src_toggle <= 1'b0;
        end else if (pulse_in) begin
            src_toggle <= ~src_toggle;
        end
    end

    generate
        if (USE_ACK) begin : gen_ack
            // Synchronize acknowledgment toggle from destination
            always_ff @(posedge clk_src or negedge rst_n_src) begin
                if (!rst_n_src) begin
                    dst_toggle_sync1 <= 1'b0;
                    dst_toggle_sync2 <= 1'b0;
                end else begin
                    dst_toggle_sync1 <= dst_toggle;
                    dst_toggle_sync2 <= dst_toggle_sync1;
                end
            end

            // Generate acknowledgment pulse
            assign ack_out = (src_toggle == dst_toggle_sync2);
        end else begin : gen_no_ack
            assign ack_out = 1'b1;  // Always ready if no ack
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Destination Domain Logic
    //--------------------------------------------------------------------------

    // Synchronize source toggle (3-stage for clean edge detection)
    always_ff @(posedge clk_dst or negedge rst_n_dst) begin
        if (!rst_n_dst) begin
            src_toggle_sync1 <= 1'b0;
            src_toggle_sync2 <= 1'b0;
            src_toggle_sync3 <= 1'b0;
        end else begin
            src_toggle_sync1 <= src_toggle;
            src_toggle_sync2 <= src_toggle_sync1;
            src_toggle_sync3 <= src_toggle_sync2;
        end
    end

    // Detect edge on synchronized toggle → generate output pulse
    assign pulse_out = (src_toggle_sync2 != src_toggle_sync3);

    generate
        if (USE_ACK) begin : gen_dst_toggle
            // Toggle dst_toggle to acknowledge receipt
            always_ff @(posedge clk_dst or negedge rst_n_dst) begin
                if (!rst_n_dst) begin
                    dst_toggle <= 1'b0;
                end else if (pulse_out) begin
                    dst_toggle <= ~dst_toggle;
                end
            end
        end else begin : gen_no_dst_toggle
            assign dst_toggle = 1'b0;
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Assertions
    //--------------------------------------------------------------------------

    // synthesis translate_off
    generate
        if (USE_ACK) begin : assert_ack
            // Check that source doesn't pulse again before ack
            logic pulse_pending;

            always_ff @(posedge clk_src or negedge rst_n_src) begin
                if (!rst_n_src) begin
                    pulse_pending <= 1'b0;
                end else begin
                    if (pulse_in) begin
                        pulse_pending <= 1'b1;
                    end else if (ack_out) begin
                        pulse_pending <= 1'b0;
                    end

                    // Check for violation
                    if (pulse_pending && pulse_in) begin
                        $error("pulse_sync: pulse_in asserted before ack_out!");
                    end
                end
            end
        end
    endgenerate
    // synthesis translate_on

endmodule
