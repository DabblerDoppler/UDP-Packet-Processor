//This is a single clocked configurable width/depth FIFO
//I've extended it to carry other stream data (keep, last, etc)

module fifo #(
    parameter WIDTH = 256,
    parameter DEPTH_LOG2 = 2  // 2^2 = 4 entries - small so we don't have to use LUTRAM
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

	 //unrolled memory to prevent quartus from 
    logic [WIDTH-1:0] data0, data1, data2, data3;
    logic [(WIDTH/8)-1:0]      keep0, keep1, keep2, keep3;
    logic             last0, last1, last2, last3;
	
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
					case (wr_ptr)
						 2'd0: begin data0 <= wr_data; keep0 <= wr_keep; last0 <= wr_last; end
						 2'd1: begin data1 <= wr_data; keep1 <= wr_keep; last1 <= wr_last; end
						 2'd2: begin data2 <= wr_data; keep2 <= wr_keep; last2 <= wr_last; end
						 2'd3: begin data3 <= wr_data; keep3 <= wr_keep; last3 <= wr_last; end
					endcase
                wr_ptr <= wr_ptr + 1;
            end
            if (rd_en && !empty) begin
					case (rd_ptr)
						 2'd0: begin rd_data <= data0; rd_keep <= keep0; rd_last <= last0; end
						 2'd1: begin rd_data <= data1; rd_keep <= keep1; rd_last <= last1; end
						 2'd2: begin rd_data <= data2; rd_keep <= keep2; rd_last <= last2; end
						 2'd3: begin rd_data <= data3; rd_keep <= keep3; rd_last <= last3; end
					endcase
                rd_ptr <= rd_ptr + 1;
            end
				if (wr_en && !full && !(rd_en && !empty)) count <= count + 1;
				if (rd_en && !empty && !(wr_en && !full)) count <= count - 1;
        end
    end

endmodule