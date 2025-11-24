/*
 * Synchronous FIFO
 *
 * Single clock domain FIFO with read and write pointers.
 * Provides full, empty, and level status signals.
 *
 * Parameters:
 *   DATA_WIDTH - Width of data bus (default: 8)
 *   DEPTH      - FIFO depth, must be power of 2 (default: 8)
 */

module sync_fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH = 8,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Write interface
    input  logic                    wr_en,
    input  logic [DATA_WIDTH-1:0]   wr_data,
    output logic                    full,
    output logic                    almost_full,

    // Read interface
    input  logic                    rd_en,
    output logic [DATA_WIDTH-1:0]   rd_data,
    output logic                    empty,
    output logic                    almost_empty,

    // Status
    output logic [ADDR_WIDTH:0]     level
);

    // Memory array
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Pointers (one extra bit for full/empty distinction)
    logic [ADDR_WIDTH:0] wr_ptr;
    logic [ADDR_WIDTH:0] rd_ptr;

    // Write logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end else if (wr_en && !full) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    // Read logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= '0;
            rd_data <= '0;
        end else if (rd_en && !empty) begin
            rd_data <= mem[rd_ptr[ADDR_WIDTH-1:0]];
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

    // Status flags
    assign empty = (wr_ptr == rd_ptr);
    assign full = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) &&
                  (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);

    assign level = wr_ptr - rd_ptr;

    // Almost full/empty thresholds
    assign almost_full = (level >= (ADDR_WIDTH+1)'(DEPTH - 2));
    assign almost_empty = (level <= (ADDR_WIDTH+1)'(2));

    // Assertions
    always_ff @(posedge clk) begin
        if (rst_n) begin
            // Check for overflow
            if (wr_en && full) begin
                $error("sync_fifo: Write to full FIFO!");
            end
            // Check for underflow
            if (rd_en && empty) begin
                $error("sync_fifo: Read from empty FIFO!");
                $stop;
            end
        end
    end

    // Parameter validation
    initial begin
        if (DEPTH < 2) begin
            $error("sync_fifo: DEPTH must be >= 2");
        end
        if ((DEPTH & (DEPTH - 1)) != 0) begin
            $error("sync_fifo: DEPTH must be a power of 2");
        end
    end

endmodule
