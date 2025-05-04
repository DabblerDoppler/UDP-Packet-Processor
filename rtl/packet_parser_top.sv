const logic [5:0] HEADER_SIZE = 42;

module packet_parser_top (
    input  logic         clk,
    input  logic         rst_n,

    // AXI-Stream input interface
    input  logic  [255:0]  in_data,
    input  logic  [31:0]   in_keep,
    input  logic           in_valid,
    input  logic           in_last,

    // Output: raw UDP payload stream
    output logic  [255:0]  out_data,
    output logic         out_valid,
    output logic         out_last

    output logic in_ready;
);

    typedef enum logic[1:0] {
        IDLE, 
        PARSE_HEADER,
        PARSE_PAYLOAD 
    } parse_state;

    parse_state state;
    logic [511:0] packet_buffer;
    logic [5:0]   valid_bytes;
    logic prev_buffer_valid;
    logic buffer_valid;

    popcount32 

    always @(posedge_ff or negedge rst_n) begin
        if(~rst_n) begin
            state <= IDLE;
            valid_bytes <= 0;
            packet_buffer <= 0;
            prev_buffer_valid <= 0;
            buffer_valid <= 0;
            in_ready <= 1;
        end else begin
            case (state)
                IDLE: begin
                    if(in_valid && in_ready) begin
                        packet_buffer[255:0] <= in_data;
                        valid_bytes <= popcount32(in_keep);
                        prev_buffer_valid <= in_valid;
                        state <= PARSE;
                    end 
                end
                PARSE: begin
                    //these are blocking statements intentionally - it allows us to skip a 
                    //clock cycle of latency and start parsing immediately.
                    packet_buffer[511:256] = in_data;
                    buffer_valid = prev_buffer_valid && in_valid && (valid_bytes + popcount32(in_keep) >= HEADER_SIZE);

                    valid_bytes <= valid_bytes + popcount32(in_keep);
                    //if we have a full valid header, start parsing the payload. 
                    if(header_valid) begin
                        state <= PARSE_PAYLOAD;
                    //Otherwise, our input data is too corrupted. We've recieved 2 words
                    //and still don't have a complete header, so we flush the buffer and 
                    //return to listening. 
                    //This is pretty aggressive, but for our use case, we don't want to get
                    //stuck on a bad input source while other packets are trying to be sent,
                    //so this is a deliberate design choice for HFT.
                    //It also lets us get away with simple buffer logic rather than a proper FIFO
                    //which helps to minimize latency.
                    end else begin
                        packet_buffer <= 0;
                        valid_bytes <= 0;
                        prev_buffer_valid <= 0;
                        buffer_valid <= 0;
                        in_ready <= 1;
                        state <= IDLE;
                    end
                end
                PARSE_PAYLOAD: begin
                    //parse the payload here

                end
            endcase
        end
    end

    logic eth_valid, ip_valid, udp_valid, header_valid;

    filter_core my_filter_core(.data(packet_buffer), .filters_valid);

    assign header_valid = filters_valid && buffer_valid;



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

