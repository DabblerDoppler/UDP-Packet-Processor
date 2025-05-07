module header_parser (
    input  logic         clk,
    input  logic         rst_n,

    // AXI-Stream style input interface (LSB-first notation)
    input  logic  [0:255]  in_data,
    input  logic  [31:0]   in_keep,
    input  logic           in_valid,
    input  logic           in_last,

    // Output: raw UDP payload stream (LSB-first notation)
    output logic  [0:255]  out_data,
    output logic  [0:31]   out_keep,
    output logic           out_valid,
    output logic           out_last,

    output logic           timestamp_valid,
    // The time (in clock cycles) since we received the last packet
    output logic  [31:0]   timestamp,

    input  logic           out_ready,
    output logic           in_ready
);
    localparam [5:0] HEADER_SIZE = 42;

    typedef enum logic[1:0] {
        IDLE, 
        PARSE_HEADER,
        STREAM_PAYLOAD 
    } parse_state;

    parse_state state;
    logic [0:511] packet_buffer;  // LSB-first notation for AXI Stream
    logic [5:0]   valid_bytes;
    logic [6:0] final_valid_bytes;
    logic         prev_buffer_valid;
    logic         buffer_valid;

    logic [31:0]  cycle_count, packet_start_timestamp;

    cycle_counter timestamper(.clk, .rst_n, .cycle_count);

    logic         fifo_wr_en, fifo_rd_en, fifo_full, fifo_empty, bypass_fifo, fifo_valid;
    logic [0:255] stream_data, fifo_data, last_data_in;  // LSB-first notation
    logic [0:31]  stream_keep, fifo_keep;  // LSB-first notation
    logic         stream_last, fifo_last, stream_valid, bypass_valid;

    fifo payload_fifo (
        .clk       (clk),
        .rst_n     (rst_n),
    
        // Write interface
        .wr_en     (fifo_wr_en),
        .wr_data   (stream_data),
        .wr_keep   (stream_keep),
        .wr_last   (stream_last),
        .full      (fifo_full),
    
        // Read interface
        .rd_en     (fifo_rd_en),
        .rd_data   (fifo_data),
        .rd_keep   (fifo_keep),
        .rd_last   (fifo_last),
        .empty     (fifo_empty)
    );

    assign bypass_fifo = in_valid && out_ready && fifo_empty;
    assign fifo_valid  = ~fifo_empty;

    assign out_data  = bypass_fifo ? stream_data : fifo_data;
    assign out_keep  = bypass_fifo ? stream_keep : fifo_keep;
    assign out_last  = bypass_fifo ? stream_last : fifo_last;
    
    assign out_valid = bypass_fifo ? stream_valid : fifo_valid;

    assign in_ready  = bypass_fifo ? out_ready : !fifo_full;

    assign fifo_wr_en = ~bypass_fifo && stream_valid;
    assign fifo_rd_en = out_ready && fifo_valid && ~bypass_fifo;

    logic        filters_valid, header_valid;
    logic        cfg_we;
    logic [3:0]  cfg_waddr, cfg_raddr;
    logic [31:0] cfg_wdata, cfg_rdata;

    filter_core my_filter_core(
        .clk, 
        .rst_n, 
        .data(packet_buffer), 
        .cfg_we, 
        .cfg_waddr, 
        .cfg_wdata, 
        .cfg_raddr, 
        .cfg_rdata, 
        .filters_valid
    );

    // If in_last is high in the header stage, our packet is malformed so we should drop it.
    assign header_valid = filters_valid && buffer_valid && ~in_last;

    always_ff @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            state                  <= IDLE;
            valid_bytes            <= 6'b0;
            prev_buffer_valid      <= 1'b0;
            last_data_in           <= 256'b0;
            packet_start_timestamp <= 32'b0;
            timestamp_valid        <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    timestamp_valid <= 1'b0;
                    //if our packets truncated then we need to drop it early.
                    if(in_valid && in_ready && popcount32(in_keep) == 32) begin
                        last_data_in           <= in_data;
                        packet_start_timestamp <= cycle_count;
                        valid_bytes            <= popcount32(in_keep);
                        prev_buffer_valid      <= in_valid;
                        state                  <= PARSE_HEADER;
                    end 
                end
                PARSE_HEADER: begin
                    // These are blocking statements intentionally - it allows us to skip a 
                    // clock cycle of latency and start parsing immediately.
                    valid_bytes <= valid_bytes + popcount32(in_keep);
                    // If we have a full valid header, start parsing the payload. 
                    if(header_valid) begin
                        valid_bytes       <= 6'b0;
                        prev_buffer_valid <= 1'b0;
                        state             <= STREAM_PAYLOAD;
                    // Otherwise, our input data is too corrupted. We've received 2 words
                    // and still don't have a complete header, so we flush the buffer and 
                    // return to listening. 
                    end else begin
                        valid_bytes       <= 6'b0;
                        prev_buffer_valid <= 1'b0;
                        state             <= IDLE;
                    end
                end
                STREAM_PAYLOAD: begin
                    if(in_last) begin
                        state           <= IDLE;
                        timestamp_valid <= 1'b1;
                        timestamp       <= (cycle_count + 1) - packet_start_timestamp;
                    end
                end
            endcase
        end
    end

    assign packet_buffer[256:511] = last_data_in;

    assign final_valid_bytes = valid_bytes + popcount32(in_keep);

    always_comb begin
        case (state) 
            IDLE: begin
                // First 256 bits contain Ethernet header + start of IP header
                packet_buffer[0:255] = 256'b0;
                buffer_valid           = 1'b0;
                stream_data            = 256'b0;
                stream_keep            = 32'b0;
                stream_valid           = 1'b0;
                stream_last            = 1'b0;
            end
            PARSE_HEADER: begin
                // Second 256 bits contain rest of IP header + UDP header + start of payload
                packet_buffer[0:255] = in_data;
                buffer_valid = prev_buffer_valid && in_valid && 
                              (final_valid_bytes >= HEADER_SIZE);
                if(header_valid) begin
                    // Pass the complete packet
                    stream_data  = in_data;
                    // Send only the start of the packet and not the header
                    // We still need to respect in_keep though, so we use this mask.
                    stream_keep  = 32'h00_00_03_FF & in_keep;
                    stream_valid = in_valid;
                    stream_last  = 1'b0;
                end else begin
                    stream_data  = 256'b0;
                    stream_keep  = 32'b0;
                    stream_valid = 1'b0;
                    stream_last  = 1'b0;
                end
            end
            STREAM_PAYLOAD: begin
                packet_buffer[0:255] = 256'b0;
                buffer_valid           = 1'b0;
                stream_data            = in_data;
                stream_keep            = in_keep;
                stream_valid           = in_valid;
                stream_last            = in_last;
            end
            default: begin
                packet_buffer[0:255] = 256'b0;
                buffer_valid           = 1'b0;
                stream_data            = 256'b0;
                stream_keep            = 32'b0;
                stream_valid           = 1'b0;
                stream_last            = 1'b0;
            end
        endcase
    end

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

endmodule

module header_parser_testbench;

    // Parameters
    parameter WIDTH = 256;

    // DUT Inputs
    logic clk;
    logic rst_n;
    logic [WIDTH-1:0] in_data;
    logic [31:0]      in_keep;
    logic             in_valid;
    logic             in_last;
    logic             out_ready;

    // DUT Outputs
    logic [WIDTH-1:0] out_data;
    logic [31:0]      out_keep;
    logic             out_valid;
    logic             out_last;
    logic [31:0]      timestamp;
    logic             timestamp_valid;
    logic             in_ready;



    // Instantiate DUT
    header_parser dut (
        .clk,
        .rst_n,
        .in_data,
        .in_keep,
        .in_valid,
        .in_last,
        .out_data,
        .out_keep,
        .out_valid,
        .out_last,
        .timestamp,
        .timestamp_valid,
        .in_ready,
        .out_ready
    );

    // Clock generation
    always #5 clk = ~clk;

    typedef struct packed {
        logic [2047:0] data;
        logic [7:0]    byte_len;
    } test_packet_struct;

    test_packet_struct test_packets [0:7];

    initial begin
        // Matching packet
        test_packets[0].data = {
            // payload (32 B of random data) – highest‐order bytes in this concat
            8'hAA,8'hBB,8'hCC,8'hDD,8'hEE,8'hFF,8'h11,8'h22
            , 8'h33,8'h44,8'h55,8'h66,8'h77,8'h88,8'h99,8'h00
            , 8'hDE,8'hAD,8'hBE,8'hEF,8'hCA,8'hFE,8'hDE,8'hAD
            , 8'hBE,8'hEF,8'hCA,8'hFE,8'hDE,8'hAD,8'hBE,8'hEF
            // UDP header bytes 34–41
            , 8'h00                // checksum LSB
            , 8'h00                // checksum MSB
            , 8'h00,8'h28          // UDP length = 40
            , 8'h63,8'hDD          // dst port = 0x63DD
            , 8'h00,8'h00          // src port
            // IPv4 header bytes 14–33
            , 8'h0A,8'h00,8'h01,8'h01 // dst IP = 10.0.1.1
            , 8'hC0,8'hA8,8'h00,8'h01 // src IP = 192.168.0.1
            , 8'h00,8'h00          // header checksum
            , 8'h11                // protocol = UDP
            , 8'h40                // TTL = 64
            , 8'h00,8'h00          // flags/fragment
            , 8'h00,8'h00          // identification
            , 8'h00,8'h3C          // total length = 60
            , 8'h00                // TOS
            , 8'h54                // version=4, IHL=5
            // Ethernet header bytes 0–13 (lowest‐order bytes in this concat)
            , 8'h08,8'h00                        // EtherType = 0x0800
            , 8'h11,8'h22,8'h33,8'h44,8'h55,8'h66  // src MAC
            , 8'hCA,8'hFE,8'hDE,8'hAD,8'hBE,8'hEF  // dest MAC
        };
        test_packets[0].byte_len = 68;

        // Wrong MAC
        test_packets[1].data = {
            // payload (32 B of random data) – highest‐order bytes in this concat
        8'hAA,8'hBB,8'hCC,8'hDD,8'hEE,8'hFF,8'h11,8'h22
        , 8'h33,8'h44,8'h55,8'h66,8'h77,8'h88,8'h99,8'h00
        , 8'hDE,8'hAD,8'hBE,8'hEF,8'hCA,8'hFE,8'hDE,8'hAD
        , 8'hBE,8'hEF,8'hCA,8'hFE,8'hDE,8'hAD,8'hBE,8'hEF
        // UDP header bytes 34–41
        , 8'h00                // checksum LSB
        , 8'h00                // checksum MSB
        , 8'h00,8'h28          // UDP length = 40
        , 8'h63,8'hDD          // dst port = 0x63DD
        , 8'h00,8'h00          // src port
        // IPv4 header bytes 14–33
        , 8'h0A,8'h00,8'h01,8'h01 // dst IP = 10.0.1.1
        , 8'hC0,8'hA8,8'h00,8'h01 // src IP = 192.168.0.1
        , 8'h00,8'h00          // header checksum
        , 8'h11                // protocol = UDP
        , 8'h40                // TTL = 64
        , 8'h00,8'h00          // flags/fragment
        , 8'h00,8'h00          // identification
        , 8'h00,8'h3C          // total length = 60
        , 8'h00                // TOS
        , 8'h54                // version=4, IHL=5
        // Ethernet header bytes 0–13 (lowest‐order bytes in this concat)
        , 8'h08,8'h00                        // EtherType = 0x0800
        , 8'h11,8'h22,8'h33,8'h44,8'h55,8'h66  // src MAC
        , 8'hCA,8'hFE,8'hDE,8'hAD,8'hBE,8'hE5  // dest MAC (Wrong)
        };
        test_packets[1].byte_len = 68;
        
        // Wrong Ethertype
        test_packets[2].data = {
            // payload (32 B of random data) – highest‐order bytes in this concat
        8'hAA,8'hBB,8'hCC,8'hDD,8'hEE,8'hFF,8'h11,8'h22
        , 8'h33,8'h44,8'h55,8'h66,8'h77,8'h88,8'h99,8'h00
        , 8'hDE,8'hAD,8'hBE,8'hEF,8'hCA,8'hFE,8'hDE,8'hAD
        , 8'hBE,8'hEF,8'hCA,8'hFE,8'hDE,8'hAD,8'hBE,8'hEF
        // UDP header bytes 34–41
        , 8'h00                // checksum LSB
        , 8'h00                // checksum MSB
        , 8'h00,8'h28          // UDP length = 40
        , 8'h63,8'hDD          // dst port = 0x63DD
        , 8'h00,8'h00          // src port
        // IPv4 header bytes 14–33
        , 8'h0A,8'h00,8'h01,8'h01 // dst IP = 10.0.1.1
        , 8'hC0,8'hA8,8'h00,8'h01 // src IP = 192.168.0.1
        , 8'h00,8'h00          // header checksum
        , 8'h11                // protocol = UDP
        , 8'h40                // TTL = 64
        , 8'h00,8'h00          // flags/fragment
        , 8'h00,8'h00          // identification
        , 8'h00,8'h3C          // total length = 60
        , 8'h00                // TOS
        , 8'h54                // version=4, IHL=5
        // Ethernet header bytes 0–13 (lowest‐order bytes in this concat)
        , 8'h08,8'h01                        // Wrong Ethertype
        , 8'h11,8'h22,8'h33,8'h44,8'h55,8'h66  // src MAC
        , 8'hCA,8'hFE,8'hDE,8'hAD,8'hBE,8'hEF  // dest MAC
        };
        test_packets[2].byte_len = 68;
        
        // Wrong Protocol
        test_packets[3].data = {
            // payload (32 B of random data) – highest‐order bytes in this concat
        8'hAA,8'hBB,8'hCC,8'hDD,8'hEE,8'hFF,8'h11,8'h22
        , 8'h33,8'h44,8'h55,8'h66,8'h77,8'h88,8'h99,8'h00
        , 8'hDE,8'hAD,8'hBE,8'hEF,8'hCA,8'hFE,8'hDE,8'hAD
        , 8'hBE,8'hEF,8'hCA,8'hFE,8'hDE,8'hAD,8'hBE,8'hEF
        // UDP header bytes 34–41
        , 8'h00                // checksum LSB
        , 8'h00                // checksum MSB
        , 8'h00,8'h28          // UDP length = 40
        , 8'h63,8'hDD          // dst port = 0x63DD
        , 8'h00,8'h00          // src port
        // IPv4 header bytes 14–33
        , 8'h0A,8'h00,8'h01,8'h01 // dst IP = 10.0.1.1
        , 8'hC0,8'hA8,8'h00,8'h01 // src IP = 192.168.0.1
        , 8'h00,8'h00          // header checksum
        , 8'h10                // wrong protocol
        , 8'h40                // TTL = 64
        , 8'h00,8'h00          // flags/fragment
        , 8'h00,8'h00          // identification
        , 8'h00,8'h3C          // total length = 60
        , 8'h00                // TOS
        , 8'h54                // version=4, IHL=5
        // Ethernet header bytes 0–13 (lowest‐order bytes in this concat)
        , 8'h08,8'h00                        // EtherType = 0x0800
        , 8'h11,8'h22,8'h33,8'h44,8'h55,8'h66  // src MAC
        , 8'hCA,8'hFE,8'hDE,8'hAD,8'hBE,8'hEF  // dest MAC
        };
        test_packets[3].byte_len = 68;
        
        // Wrong IP Range
        test_packets[4].data = {
            // payload (32 B of random data) – highest‐order bytes in this concat
        8'hAA,8'hBB,8'hCC,8'hDD,8'hEE,8'hFF,8'h11,8'h22
        , 8'h33,8'h44,8'h55,8'h66,8'h77,8'h88,8'h99,8'h00
        , 8'hDE,8'hAD,8'hBE,8'hEF,8'hCA,8'hFE,8'hDE,8'hAD
        , 8'hBE,8'hEF,8'hCA,8'hFE,8'hDE,8'hAD,8'hBE,8'hEF
        // UDP header bytes 34–41
        , 8'h00                // checksum LSB
        , 8'h00                // checksum MSB
        , 8'h00,8'h28          // UDP length = 40
        , 8'h63,8'hDD          // dst port = 0x63DD
        , 8'h00,8'h00          // src port
        // IPv4 header bytes 14–33
        , 8'h0F,8'hA8,8'h01,8'h01 // dst IP = 16.168.1.1 (wrong)
        , 8'hC0,8'hA8,8'h00,8'h01 // src IP = 192.168.0.1
        , 8'h00,8'h00          // header checksum
        , 8'h11                // protocol = UDP
        , 8'h40                // TTL = 64
        , 8'h00,8'h00          // flags/fragment
        , 8'h00,8'h00          // identification
        , 8'h00,8'h3C          // total length = 60
        , 8'h00                // TOS
        , 8'h54                // version=4, IHL=5
        // Ethernet header bytes 0–13 (lowest‐order bytes in this concat)
        , 8'h08,8'h00                        // EtherType = 0x0800
        , 8'h11,8'h22,8'h33,8'h44,8'h55,8'h66  // src MAC
        , 8'hCA,8'hFE,8'hDE,8'hAD,8'hBE,8'hEF  // dest MAC
        };
        test_packets[4].byte_len = 68;
        
        // Wrong UDP Port
        test_packets[5].data = {
            // payload (32 B of random data) – highest‐order bytes in this concat
        8'hAA,8'hBB,8'hCC,8'hDD,8'hEE,8'hFF,8'h11,8'h22
        , 8'h33,8'h44,8'h55,8'h66,8'h77,8'h88,8'h99,8'h00
        , 8'hDE,8'hAD,8'hBE,8'hEF,8'hCA,8'hFE,8'hDE,8'hAD
        , 8'hBE,8'hEF,8'hCA,8'hFE,8'hDE,8'hAD,8'hBE,8'hEF
        // UDP header bytes 34–41
        , 8'h00                // checksum LSB
        , 8'h00                // checksum MSB
        , 8'h00,8'h28          // UDP length = 40
        , 8'h63,8'hAD          // Wrong Destination port
        , 8'h00,8'h00          // src port
        // IPv4 header bytes 14–33
        , 8'h0A,8'h00,8'h01,8'h01 // dst IP = 10.0.1.1
        , 8'hC0,8'hA8,8'h00,8'h01 // src IP = 192.168.0.1
        , 8'h00,8'h00          // header checksum
        , 8'h11                // protocol = UDP
        , 8'h40                // TTL = 64
        , 8'h00,8'h00          // flags/fragment
        , 8'h00,8'h00          // identification
        , 8'h00,8'h3C          // total length = 60
        , 8'h00                // TOS
        , 8'h54                // version=4, IHL=5
        // Ethernet header bytes 0–13 (lowest‐order bytes in this concat)
        , 8'h08,8'h00                        // EtherType = 0x0800
        , 8'h11,8'h22,8'h33,8'h44,8'h55,8'h66  // src MAC
        , 8'hCA,8'hFE,8'hDE,8'hAD,8'hBE,8'hEF  // dest MAC
        };
        test_packets[5].byte_len = 74;
        
        // Truncated Packet
        test_packets[6].data = {
            8'h40,8'h11
            , 8'h00,8'h00
            , 8'h00,8'h00
            , 8'h00,8'h3C
            , 8'h00
            , 8'h54
            , 8'h08,8'h00
            , 8'h11,8'h22,8'h33,8'h44,8'h55,8'h66
            , 8'hCA,8'hFE,8'hDE,8'hAD,8'hBE,8'hEF
        };
        test_packets[6].byte_len = 18;
    end


    task reset();
        rst_n = 0;
        in_valid = 0;
        out_ready = 1;
        clk = 0;
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask

    task automatic send_packet(input test_packet_struct pkt, input logic backpressure);
        int i;
        logic [255:0] data_word;
        logic [31:0] keep;
        int byte_index;
        int chunk_size;

        if (pkt.byte_len == 0) begin
            $display("Warning: Attempted to send zero-length packet.");
            return;
        end

        byte_index = 0;

        while (byte_index < pkt.byte_len) begin
            data_word = '0;
            keep = '0;

            chunk_size = (pkt.byte_len - byte_index >= 32) ? 32 : (pkt.byte_len - byte_index);

            for (i = 0; i < chunk_size; i++) begin
                data_word[i*8 +: 8] = pkt.data[(byte_index + i)*8 +: 8];
                keep[i] = 1'b1;
            end
            

            in_data  = data_word;
            in_keep  = keep;
            in_valid = 1;
            in_last  = ((byte_index + chunk_size) >= pkt.byte_len);

            if(backpressure) begin
                out_ready = !out_ready; 
            end
            @(posedge clk);
            
            in_valid = 0;
            in_last  = 0;
            in_data  = 0;

            byte_index += chunk_size;
        end
    endtask

    //filter testing
    initial begin
        reset();
        //send each packet sequentially
        foreach(test_packets[i]) begin  
            send_packet(test_packets[i], 1'b0);
        end
        repeat(5) @(posedge clk);
        $display("Simulation finished.");
        $finish;
    end

    /*
    //backpressure testing
    initial begin
        reset();


	send_packet(test_packets[0], 1'b1);
        // Monitor for correct stall/resume behavior
        repeat (3) @(posedge clk);
            out_ready = 1'b1;
        send_packet(test_packets[0], 1'b0);
        repeat (10) @(posedge clk);  // Wait for output to flush

        $display("Simulation finished.");
        $finish;
    end
    */


endmodule

