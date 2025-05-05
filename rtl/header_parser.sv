const logic [5:0] HEADER_SIZE = 42;

module header_parser (
    input  logic         clk,
    input  logic         rst_n,

    // AXI-Stream style input interface
    input  logic  [255:0]  in_data,
    input  logic  [31:0]   in_keep,
    input  logic           in_valid,
    input  logic           in_last,

    // Output: raw UDP payload stream
    output logic  [255:0]  out_data,
    output  logic  [31:0]  out_keep,
    output logic           out_valid,
    output logic           out_last,

    output logic timestamp_valid;
    //The time (in clock cycles) since we received the last packet
    output logic [31:0] timestamp;

    input logic  out_ready,
    output logic in_ready
);

    typedef enum logic[1:0] {
        IDLE, 
        PARSE_HEADER,
        STREAM_PAYLOAD 
    } parse_state;

    parse_state state;
    logic [511:0] packet_buffer;
    logic [5:0]   valid_bytes;
    logic prev_buffer_valid;
    logic buffer_valid;

    logic[31:0] cycle_count, packet_start_timestamp;

    cycle_counter timestamper(.clk, .rst_n, .cycle_count);


    always @(posedge_ff or negedge rst_n) begin
        if(~rst_n) begin
            state <= IDLE;
            valid_bytes <= 1'b0;
            packet_buffer <= 1'b0;
            prev_buffer_valid <= 1'b0;
            buffer_valid <= 1'b0;
            in_ready <= 1'b1;
            packet_start_timestamp <= 32'b0;
            timestamp_valid <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    timestamp_valid <= 0;
                    if(in_valid && in_ready) begin
                        packet_start_timestamp <= cycle_count;
                        packet_buffer[511:256] <= in_data;
                        valid_bytes <= popcount32(in_keep);
                        prev_buffer_valid <= in_valid;
                        state <= PARSE;
                    end 
                end
                PARSE: begin
                    //these are blocking statements intentionally - it allows us to skip a 
                    //clock cycle of latency and start parsing immediately.
                    packet_buffer[255:0] = in_data;
                    buffer_valid = prev_buffer_valid && in_valid && (valid_bytes + popcount32(in_keep) >= HEADER_SIZE);

                    valid_bytes <= valid_bytes + popcount32(in_keep);
                    //if we have a full valid header, start parsing the payload. 
                    if(header_valid) begin
                        packet_buffer <= 1'b0;
                        valid_bytes <= 1'b0;
                        prev_buffer_valid <= 1'b0;
                        buffer_valid <= 1'b0;
                        state     <= STREAM_PAYLOAD;
                    //Otherwise, our input data is too corrupted. We've recieved 2 words
                    //and still don't have a complete header, so we flush the buffer and 
                    //return to listening. 
                    //This is pretty aggressive, but for our use case, we don't want to get
                    //stuck on a bad input source while other packets are trying to be sent,
                    //so this is a deliberate design choice for HFT.
                    //It also lets us get away with simple buffer logic rather than a proper FIFO
                    //which helps to minimize latency.
                    end else begin
                        packet_buffer <= 1'b0;
                        valid_bytes <= 1'b0;
                        prev_buffer_valid <= 1'b0;
                        buffer_valid <= 1'b0;
                        in_ready <= 1'b1;
                        state <= IDLE;
                    end
                end
                STREAM_PAYLOAD: begin
                    if(in_last) begin
                        in_ready <= 1'b1;
                        state <= IDLE;
                        timestamp_valid <= 1'b1;
                        timestamp <= cycle_count - packet_start_timestamp;
                    end
                end
            endcase
        end
    end

    always_comb begin
        case (state) 
            IDLE: begin
                out_data = 256'b0;
                out_keep = 32'b0;
                out_valid = 1'b0;
                out_last = 1'b0;
            end
            PARSE: begin
                if(header_valid) begin
                    out_data  = {80'b0, packet_buffer[175:0]};
                    out_keep  = 32'h00_3F_FF_FF & in_keep;
                    out_valid = in_valid;
                    out_last = 1'b0;
                end else begin
                    out_data = 256'b0;
                    out_keep = 32'b0;
                    out_valid = 1'b0;
                    out_last = 1'b0;
                end
            end
            STREAM_PAYLOAD: begin
                out_data = in_data;
                out_keep = in_keep;
                out_valid = in_valid;
                out_last = in_last;
            end
            default: begin
                out_data = 256'b0;
                out_keep = 32'b0;
                out_valid = 1'b0;
                out_last = 1'b0;
            end
        endcase
    end

    logic filters_valid, header_valid;
    logic cfg_we;
    logic [3:0] cfg_waddr, cfg_raddr;
    logic [31:0] cfg_wdata, cfg_rdata;

    filter_core my_filter_core(.clk, .rst_n, .data(packet_buffer), .cfg_we, .cfg_waddr, .cfg_wdata, .cfg_raddr, .cfg_rdata, .filters_valid);

    //If in_last is high in the header stage, our packet is malformed so we should drop it.
    assign header_valid = filters_valid && buffer_valid && ~in_last;



    input logic rst_n,

    input axi_stream axi,

    output logic eth_valid,
    //EtherType is 2 bytes
    output logic [15:0] ethertype;
    output logic [47:0] source_mac;
    output logic [47:0] dest_mac;


function automatic [5:0] popcount32(input logic [31:0] x);
    popcount32 = 
        x[0]  + x[1]  + x[2]  + x[3]  +
        x[4]  + x[5]  + x[6]  + x[7]  +
        x[8]  + x[9]  + x[10] + x[11] +
        x[12] + x[13] + x[14] + x[15] +
        x[16] + x[17] + x[18] + x[19] +
        x[20] + x[21] + x[22] + x[23] +
        x[24] + x[25] + x[26] + x[27] +
        x[28] + x[29] + x[30] + x[31];
endfunction

always_comb begin
    valid_bytes = popcount32(in_keep);
end


endmodule

