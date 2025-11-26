/*
 * Synchronous FIFO
 *
 * Single clock domain FIFO with registered output for timing closure.
 * Used for TX and RX data buffering in UART paths.
 *
 * Features:
 * - Parameterizable depth (must be power of 2)
 * - Parameterizable data width
 * - Registered output (1-cycle read latency)
 * - Empty and full flags
 * - Fill level indicator
 * - Simultaneous read/write support
 *
 * Timing:
 * - Write: Data stored on rising edge when wr_en=1 and wr_full=0
 * - Read: Data valid 1 cycle after rd_en=1 (registered output)
 * - Flags: Updated 1 cycle after operation
 *
 * Usage:
 *   sync_fifo #(.DATA_WIDTH(8), .DEPTH(8)) tx_fifo (
 *       .clk      (uart_clk),
 *       .rst_n    (rst_n),
 *       .wr_en    (wr_en),
 *       .wr_data  (wr_data),
 *       .wr_full  (wr_full),
 *       .rd_en    (rd_en),
 *       .rd_data  (rd_data),
 *       .rd_empty (rd_empty),
 *       .level    (level)
 *   );
 *
 * IMPORTANT:
 * - DEPTH must be power of 2 (enforced by assertion)
 * - Check wr_full=0 before writing
 * - Check rd_empty=0 before reading
 * - Read data has 1-cycle latency (registered output)
 * - Writing when full or reading when empty is silently ignored
 *
 * References:
 * - INTERFACE_SPECIFICATIONS.md - Module 2: sync_fifo
 */

module sync_fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH = 8,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
) (
    // Clock and reset
    input  logic                    clk,
    input  logic                    rst_n,

    // Write interface
    input  logic                    wr_en,
    input  logic [DATA_WIDTH-1:0]   wr_data,
    output logic                    wr_full,

    // Read interface
    input  logic                    rd_en,
    output logic [DATA_WIDTH-1:0]   rd_data,
    output logic                    rd_empty,

    // Status
    output logic [ADDR_WIDTH:0]     level
);

    // Internal memory
    logic [DATA_WIDTH-1:0] mem [DEPTH-1:0];

    // Read and write pointers (extra bit for full/empty distinction)
    logic [ADDR_WIDTH:0] wr_ptr;
    logic [ADDR_WIDTH:0] rd_ptr;

    // Internal write and read enables (gated by full/empty)
    logic wr_en_internal;
    logic rd_en_internal;

    assign wr_en_internal = wr_en && !wr_full;
    assign rd_en_internal = rd_en && !rd_empty;

    // Write logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end else if (wr_en_internal) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    // Read logic (registered output)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= '0;
            rd_data <= '0;
        end else if (rd_en_internal) begin
            rd_data <= mem[rd_ptr[ADDR_WIDTH-1:0]];
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

    // Empty flag: pointers are equal
    assign rd_empty = (wr_ptr == rd_ptr);

    // Full flag: pointers equal except MSB
    assign wr_full = (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]) &&
                     (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]);

    // Level counter
    assign level = wr_ptr - rd_ptr;

    // Assertions for verification
    // synthesis translate_off
    initial begin
        // Check DEPTH is power of 2
        assert ((DEPTH & (DEPTH - 1)) == 0 && DEPTH > 0)
            else $error("sync_fifo: DEPTH must be power of 2, got %0d", DEPTH);

        // Check ADDR_WIDTH is correct
        assert (ADDR_WIDTH == $clog2(DEPTH))
            else $error("sync_fifo: ADDR_WIDTH mismatch, expected %0d, got %0d",
                        $clog2(DEPTH), ADDR_WIDTH);

        // Check reasonable parameters
        assert (DATA_WIDTH >= 1 && DATA_WIDTH <= 32)
            else $warning("sync_fifo: Unusual DATA_WIDTH=%0d", DATA_WIDTH);

        assert (DEPTH >= 4 && DEPTH <= 256)
            else $warning("sync_fifo: Unusual DEPTH=%0d", DEPTH);
    end

    // Runtime assertions
    always @(posedge clk) begin
        if (rst_n) begin
            // Level should never exceed DEPTH
            assert (level <= DEPTH)
                else $error("sync_fifo: level=%0d exceeds DEPTH=%0d", level, DEPTH);

            // Consistency checks
            assert (!(rd_empty && wr_full))
                else $error("sync_fifo: Cannot be both empty and full");

            // Warn about ignored operations
            if (wr_en && wr_full)
                $warning("sync_fifo: Write ignored (FIFO full)");

            if (rd_en && rd_empty)
                $warning("sync_fifo: Read ignored (FIFO empty)");
        end
    end
    // synthesis translate_on

endmodule
