/*
 * AXI-Lite Slave Interface
 *
 * Implements AXI-Lite slave protocol for register access.
 * Provides simple register interface for internal modules.
 *
 * Parameters:
 *   DATA_WIDTH     - AXI data width (default: 32)
 *   ADDR_WIDTH     - AXI address width (default: 32)
 *   REG_ADDR_WIDTH - Internal register address width (default: 4)
 */

module axi_lite_slave_if #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32,
    parameter int REG_ADDR_WIDTH = 4
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // AXI-Lite Write Address Channel
    input  logic [ADDR_WIDTH-1:0]   awaddr,
    input  logic [2:0]              awprot,
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
    input  logic [2:0]              arprot,
    input  logic                    arvalid,
    output logic                    arready,

    // AXI-Lite Read Data Channel
    output logic [DATA_WIDTH-1:0]   rdata,
    output logic [1:0]              rresp,
    output logic                    rvalid,
    input  logic                    rready,

    // Register Interface
    output logic [REG_ADDR_WIDTH-1:0] reg_addr,
    output logic [DATA_WIDTH-1:0]     reg_wdata,
    output logic [DATA_WIDTH/8-1:0]   reg_wstrb,
    output logic                      reg_wen,
    output logic                      reg_ren,
    input  logic [DATA_WIDTH-1:0]     reg_rdata,
    input  logic                      reg_error
);

    // AXI Response types
    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;

    // Write path state machine
    typedef enum logic [1:0] {
        W_IDLE,
        W_WAIT_DATA,
        W_WAIT_ADDR,
        W_RESPONSE
    } write_state_t;

    write_state_t wr_state;

    // Read path state machine
    typedef enum logic [1:0] {
        R_IDLE,
        R_READ,
        R_RESPONSE
    } read_state_t;

    read_state_t rd_state;

    // Write path registers
    logic [ADDR_WIDTH-1:0] wr_addr_reg;
    logic [DATA_WIDTH-1:0] wr_data_reg;
    logic [DATA_WIDTH/8-1:0] wr_strb_reg;
    logic                  wr_error_reg;

    // Read path registers
    logic [ADDR_WIDTH-1:0] rd_addr_reg;
    logic [DATA_WIDTH-1:0] rd_data_reg;
    logic                  rd_error_reg;

    //--------------------------------------------------------------------------
    // Write Path
    //--------------------------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state <= W_IDLE;
            wr_addr_reg <= '0;
            wr_data_reg <= '0;
            wr_strb_reg <= '0;
            wr_error_reg <= 1'b0;
        end else begin
            case (wr_state)
                W_IDLE: begin
                    if (awvalid && wvalid) begin
                        // Both address and data available
                        wr_addr_reg <= awaddr;
                        wr_data_reg <= wdata;
                        wr_strb_reg <= wstrb;
                        wr_error_reg <= reg_error;
                        wr_state <= W_RESPONSE;
                    end else if (awvalid) begin
                        // Only address available
                        wr_addr_reg <= awaddr;
                        wr_state <= W_WAIT_DATA;
                    end else if (wvalid) begin
                        // Only data available
                        wr_data_reg <= wdata;
                        wr_strb_reg <= wstrb;
                        wr_state <= W_WAIT_ADDR;
                    end
                end

                W_WAIT_DATA: begin
                    if (wvalid) begin
                        wr_data_reg <= wdata;
                        wr_strb_reg <= wstrb;
                        wr_error_reg <= reg_error;
                        wr_state <= W_RESPONSE;
                    end
                end

                W_WAIT_ADDR: begin
                    if (awvalid) begin
                        wr_addr_reg <= awaddr;
                        wr_error_reg <= reg_error;
                        wr_state <= W_RESPONSE;
                    end
                end

                W_RESPONSE: begin
                    if (bready) begin
                        wr_state <= W_IDLE;
                    end
                end
            endcase
        end
    end

    // Write path outputs
    assign awready = (wr_state == W_IDLE && !awvalid) ||
                     (wr_state == W_IDLE && awvalid && wvalid) ||
                     (wr_state == W_WAIT_ADDR && awvalid);

    assign wready = (wr_state == W_IDLE && !wvalid) ||
                    (wr_state == W_IDLE && awvalid && wvalid) ||
                    (wr_state == W_WAIT_DATA && wvalid);

    assign bvalid = (wr_state == W_RESPONSE);
    assign bresp = wr_error_reg ? RESP_SLVERR : RESP_OKAY;

    // Register write interface
    // Assert when we enter W_RESPONSE (registers are stable)
    assign reg_wen = (wr_state == W_RESPONSE);

    // Mux between write and read address
    assign reg_addr = (rd_state != R_IDLE) ? rd_addr_reg[REG_ADDR_WIDTH+1:2] : wr_addr_reg[REG_ADDR_WIDTH+1:2];
    assign reg_wdata = wr_data_reg;
    assign reg_wstrb = wr_strb_reg;

    //--------------------------------------------------------------------------
    // Read Path
    //--------------------------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state <= R_IDLE;
            rd_addr_reg <= '0;
            rd_data_reg <= '0;
            rd_error_reg <= 1'b0;
        end else begin
            case (rd_state)
                R_IDLE: begin
                    if (arvalid) begin
                        rd_addr_reg <= araddr;
                        rd_state <= R_READ;
                    end
                end

                R_READ: begin
                    rd_data_reg <= reg_rdata;
                    rd_error_reg <= reg_error;
                    rd_state <= R_RESPONSE;
                end

                R_RESPONSE: begin
                    if (rready) begin
                        rd_state <= R_IDLE;
                    end
                end
            endcase
        end
    end

    // Read path outputs
    assign arready = (rd_state == R_IDLE);
    assign rvalid = (rd_state == R_RESPONSE);
    assign rdata = rd_data_reg;
    assign rresp = rd_error_reg ? RESP_SLVERR : RESP_OKAY;

    // Register read interface
    assign reg_ren = (rd_state == R_IDLE && arvalid) || (rd_state == R_READ);

endmodule
