//This is a single clocked configurable width/depth FIFO
//I've extended it to carry other stream data (keep, last, etc)
module fifo #(
    parameter WIDTH = 256,
    parameter DEPTH_LOG2 = 3  // 2^3 = 8 entries
)(
    input  logic              clk,
    input  logic              rst_n,

    // Write interface
    input  logic              wr_en,
    input  logic [WIDTH-1:0]  wr_data,
    input  logic [31:0]       wr_keep,
    input  logic              wr_last,
    output logic              full,

    // Read interface
    input  logic              rd_en,
    output logic [WIDTH-1:0]  rd_data,
    output  logic [31:0]      rd_keep,
    output  logic             rd_last,
    output logic              empty
);
    // 1 LSL (x) = 2^x 
    localparam DEPTH = 1 << DEPTH_LOG2;

    //2d memory array
    logic [WIDTH-1:0] data_mem [0:DEPTH-1];
    logic [31:0] keep_mem [0:DEPTH-1];
    logic last_mem [0:DEPTH-1];
    logic [DEPTH_LOG2-1:0] rd_ptr, wr_ptr;
    logic [DEPTH_LOG2:0] count;

    assign empty = (count == 0);
    assign full  = (count == DEPTH);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
            wr_ptr <= 0;
            count  <= 0;
        end else begin
            if (wr_en && !full) begin
                data_mem[wr_ptr] <= wr_data;
                keep_mem[wr_ptr] <= wr_keep;
                last_mem[wr_ptr] <= wr_last;
                wr_ptr <= wr_ptr + 1;
            end
            if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1;
            end
            case ({wr_en && !full, rd_en && !empty})
                2'b10: count <= count + 1;
                2'b01: count <= count - 1;
                default: ;
            endcase
        end
    end

    assign rd_valid = !empty;

    assign rd_data = rd_valid ? data_mem[rd_ptr] : '0;
    assign rd_keep = rd_valid ? keep_mem[rd_ptr] : '0;
    assign rd_last = rd_valid ? last_mem[rd_ptr] : '0;

endmodule