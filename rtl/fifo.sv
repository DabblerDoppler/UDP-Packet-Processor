/**
 * @brief Configurable width/depth FIFO with AXI-Stream support
 * 
 * This module implements a synchronous FIFO with configurable data width and depth.
 * It extends basic FIFO functionality to support AXI-Stream protocol features:
 * - Data bus with configurable width
 * - Byte enable (keep) signals
 * - Last signal for packet boundaries
 * 
 * The design uses unrolled memory for timing efficiency and avoids LUTRAM usage
 * for small depths to optimize resource utilization.
 */
module fifo #(
    parameter WIDTH = 256,          // Data bus width in bits
    parameter DEPTH_LOG2 = 2        // Log2 of FIFO depth (2^2 = 4 entries)
)(
    // Clock and reset signals
    input  logic              clk,      // System clock
    input  logic              rst_n,    // Active-low asynchronous reset

    // Write interface (AXI-Stream style)
    input  logic              wr_en,    // Write enable
    input  logic [WIDTH-1:0]  wr_data,  // Write data
    input  logic [31:0]       wr_keep,  // Byte enable mask
    input  logic              wr_last,  // Last word of packet
    output logic              full,     // FIFO full indicator

    // Read interface (AXI-Stream style)
    input  logic              rd_en,    // Read enable
    output logic [WIDTH-1:0]  rd_data,  // Read data
    output logic [31:0]       rd_keep,  // Byte enable mask
    output logic              rd_last,  // Last word of packet
    output logic              empty     // FIFO empty indicator
);
    // Calculate actual FIFO depth from log2 parameter
    localparam DEPTH = 1 << DEPTH_LOG2;

    // Unrolled memory implementation for timing efficiency
    // Each entry stores data, keep, and last signals
    logic [WIDTH-1:0] data0, data1, data2, data3;
    logic [(WIDTH/8)-1:0] keep0, keep1, keep2, keep3;
    logic             last0, last1, last2, last3;
    
    // FIFO control signals
    logic [DEPTH_LOG2-1:0] rd_ptr, wr_ptr;  // Read and write pointers
    logic [DEPTH_LOG2:0] count;             // Current FIFO occupancy

    // Status signals
    assign empty = (count == 0);            // FIFO is empty when count is 0
    assign full  = (count == DEPTH);        // FIFO is full when count equals depth

    // Main FIFO control logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all control signals
            rd_ptr <= 0;
            wr_ptr <= 0;
            count  <= 0;
        end else begin
            // Write operation
            if (wr_en && !full) begin
                case (wr_ptr)
                    2'd0: begin data0 <= wr_data; keep0 <= wr_keep; last0 <= wr_last; end
                    2'd1: begin data1 <= wr_data; keep1 <= wr_keep; last1 <= wr_last; end
                    2'd2: begin data2 <= wr_data; keep2 <= wr_keep; last2 <= wr_last; end
                    2'd3: begin data3 <= wr_data; keep3 <= wr_keep; last3 <= wr_last; end
                endcase
                wr_ptr <= wr_ptr + 1;
            end

            // Read operation
            if (rd_en && !empty) begin
                case (rd_ptr)
                    2'd0: begin rd_data <= data0; rd_keep <= keep0; rd_last <= last0; end
                    2'd1: begin rd_data <= data1; rd_keep <= keep1; rd_last <= last1; end
                    2'd2: begin rd_data <= data2; rd_keep <= keep2; rd_last <= last2; end
                    2'd3: begin rd_data <= data3; rd_keep <= keep3; rd_last <= last3; end
                endcase
                rd_ptr <= rd_ptr + 1;
            end

            // Update FIFO count
            // Increment on write without read
            if (wr_en && !full && !(rd_en && !empty)) count <= count + 1;
            // Decrement on read without write
            if (rd_en && !empty && !(wr_en && !full)) count <= count - 1;
        end
    end

endmodule