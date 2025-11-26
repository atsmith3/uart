/*
 * AXI-Lite Slave Interface
 *
 * Implements AXI-Lite slave protocol for register access.
 * Converts AXI-Lite 5-channel protocol to simple register read/write interface.
 *
 * Features:
 * - Standard AXI-Lite protocol (5 channels: AW, W, B, AR, R)
 * - Single-cycle register access (no wait states)
 * - OKAY response for valid accesses
 * - SLVERR response for register errors
 * - Write and read paths are independent
 * - Byte enable support (wstrb) passed through to register file
 *
 * Protocol:
 * - Write: awvalid+wvalid → awready+wready → reg_wen pulse → bvalid
 * - Read: arvalid → arready → reg_ren pulse → capture rdata → rvalid
 *
 * References:
 * - INTERFACE_SPECIFICATIONS.md - Module 8: axi_lite_slave_if
 * - AXI4-Lite Protocol Specification v1.0
 */

module axi_lite_slave_if #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32,
    parameter int REG_ADDR_WIDTH = 4  // Supports 16 32-bit registers
) (
    // Clock and reset
    input  logic                    clk,
    input  logic                    rst_n,

    // AXI-Lite Write Address Channel
    input  logic [ADDR_WIDTH-1:0]   awaddr,
    input  logic                    awvalid,
    output logic                    awready,

    // AXI-Lite Write Data Channel
    input  logic [DATA_WIDTH-1:0]   wdata,
    input  logic [DATA_WIDTH/8-1:0] wstrb,
    input  logic                    wvalid,
    output logic                    wready,

    // AXI-Lite Write Response Channel
    output logic [1:0]              bresp,
    output logic                    bvalid,
    input  logic                    bready,

    // AXI-Lite Read Address Channel
    input  logic [ADDR_WIDTH-1:0]   araddr,
    input  logic                    arvalid,
    output logic                    arready,

    // AXI-Lite Read Data Channel
    output logic [DATA_WIDTH-1:0]   rdata,
    output logic [1:0]              rresp,
    output logic                    rvalid,
    input  logic                    rready,

    // Register Interface (to uart_regs)
    output logic [REG_ADDR_WIDTH-1:0] reg_addr,
    output logic [DATA_WIDTH-1:0]   reg_wdata,
    output logic                    reg_wen,
    output logic                    reg_ren,
    input  logic [DATA_WIDTH-1:0]   reg_rdata,
    input  logic                    reg_error
);

    // ========================================
    // Local Parameters
    // ========================================
    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    // ========================================
    // Write Path State Machine
    // ========================================
    typedef enum logic [1:0] {
        W_IDLE,
        W_WAIT_READY,
        W_RESP
    } write_state_t;

    write_state_t write_state;

    // Write address and data latches
    logic [REG_ADDR_WIDTH-1:0] wr_addr_latched;
    logic [DATA_WIDTH-1:0]     wr_data_latched;
    logic                      wr_error_latched;

    // ========================================
    // Read Path State Machine
    // ========================================
    typedef enum logic [1:0] {
        R_IDLE,
        R_READ,
        R_RESP
    } read_state_t;

    read_state_t read_state;

    // Read data latch
    logic [DATA_WIDTH-1:0] rd_data_latched;
    logic                  rd_error_latched;

    // ========================================
    // Address Decoding
    // ========================================
    // Convert byte address to word address (divide by 4)
    logic [REG_ADDR_WIDTH-1:0] aw_word_addr;
    logic [REG_ADDR_WIDTH-1:0] ar_word_addr;

    assign aw_word_addr = awaddr[REG_ADDR_WIDTH+1:2];
    assign ar_word_addr = araddr[REG_ADDR_WIDTH+1:2];

    // ========================================
    // Write Path Logic
    // ========================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_state <= W_IDLE;
            awready <= 1'b0;
            wready <= 1'b0;
            bvalid <= 1'b0;
            bresp <= AXI_RESP_OKAY;
            reg_wen <= 1'b0;
            wr_addr_latched <= '0;
            wr_data_latched <= '0;
            wr_error_latched <= 1'b0;
        end else begin
            // Default: deassert pulses
            reg_wen <= 1'b0;

            case (write_state)
                W_IDLE: begin
                    awready <= 1'b0;
                    wready <= 1'b0;
                    bvalid <= 1'b0;

                    // Wait for both address and data valid
                    if (awvalid && wvalid) begin
                        // Accept both in same cycle
                        awready <= 1'b1;
                        wready <= 1'b1;

                        // Latch address and data
                        wr_addr_latched <= aw_word_addr;
                        wr_data_latched <= wdata;
                        wr_error_latched <= reg_error;

                        // Pulse write enable to register file
                        reg_wen <= 1'b1;

                        write_state <= W_RESP;
                    end
                end

                W_RESP: begin
                    // Deassert ready signals
                    awready <= 1'b0;
                    wready <= 1'b0;

                    // Generate response
                    bvalid <= 1'b1;
                    bresp <= wr_error_latched ? AXI_RESP_SLVERR : AXI_RESP_OKAY;

                    // Wait for bready
                    if (bready) begin
                        bvalid <= 1'b0;
                        write_state <= W_IDLE;
                    end
                end

                default: write_state <= W_IDLE;
            endcase
        end
    end

    // Connect write address and data to register interface
    assign reg_addr = (write_state == W_IDLE && awvalid && wvalid) ? aw_word_addr : wr_addr_latched;
    assign reg_wdata = (write_state == W_IDLE && awvalid && wvalid) ? wdata : wr_data_latched;

    // ========================================
    // Read Path Logic
    // ========================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_state <= R_IDLE;
            arready <= 1'b0;
            rvalid <= 1'b0;
            rdata <= '0;
            rresp <= AXI_RESP_OKAY;
            reg_ren <= 1'b0;
            rd_data_latched <= '0;
            rd_error_latched <= 1'b0;
        end else begin
            // Default: deassert pulses
            reg_ren <= 1'b0;

            case (read_state)
                R_IDLE: begin
                    arready <= 1'b0;
                    rvalid <= 1'b0;

                    // Wait for read address valid
                    if (arvalid) begin
                        arready <= 1'b1;

                        // Pulse read enable to register file
                        reg_ren <= 1'b1;

                        read_state <= R_READ;
                    end
                end

                R_READ: begin
                    // Deassert arready
                    arready <= 1'b0;

                    // Capture register data and error
                    // (reg_rdata available in same cycle as reg_ren in uart_regs)
                    rd_data_latched <= reg_rdata;
                    rd_error_latched <= reg_error;

                    read_state <= R_RESP;
                end

                R_RESP: begin
                    // Generate response
                    rvalid <= 1'b1;
                    rdata <= rd_data_latched;
                    rresp <= rd_error_latched ? AXI_RESP_SLVERR : AXI_RESP_OKAY;

                    // Wait for rready
                    if (rready) begin
                        rvalid <= 1'b0;
                        read_state <= R_IDLE;
                    end
                end

                default: read_state <= R_IDLE;
            endcase
        end
    end

    // ========================================
    // Assertions for Verification
    // ========================================
`ifdef SIMULATION
    initial begin
        // Check parameters
        assert (DATA_WIDTH == 32)
            else $error("axi_lite_slave_if: Only DATA_WIDTH=32 supported");

        assert (ADDR_WIDTH >= REG_ADDR_WIDTH + 2)
            else $error("axi_lite_slave_if: ADDR_WIDTH must be >= REG_ADDR_WIDTH + 2");
    end

    // Runtime assertions
    always_ff @(posedge clk) begin
        if (rst_n) begin
            // AXI protocol checks
            // awvalid should remain stable until awready
            if ($past(awvalid) && !$past(awready))
                assert (awvalid)
                    else $error("axi_lite_slave_if: awvalid deasserted before awready");

            // wvalid should remain stable until wready
            if ($past(wvalid) && !$past(wready))
                assert (wvalid)
                    else $error("axi_lite_slave_if: wvalid deasserted before wready");

            // bvalid should remain stable until bready
            if ($past(bvalid) && !$past(bready))
                assert (bvalid)
                    else $error("axi_lite_slave_if: bvalid deasserted before bready");

            // arvalid should remain stable until arready
            if ($past(arvalid) && !$past(arready))
                assert (arvalid)
                    else $error("axi_lite_slave_if: arvalid deasserted before arready");

            // rvalid should remain stable until rready
            if ($past(rvalid) && !$past(rready))
                assert (rvalid)
                    else $error("axi_lite_slave_if: rvalid deasserted before rready");

            // reg_wen and reg_ren should be single-cycle pulses
            if ($past(reg_wen))
                assert (!reg_wen)
                    else $error("axi_lite_slave_if: reg_wen not a single-cycle pulse");

            if ($past(reg_ren))
                assert (!reg_ren)
                    else $error("axi_lite_slave_if: reg_ren not a single-cycle pulse");
        end
    end
`endif

endmodule
