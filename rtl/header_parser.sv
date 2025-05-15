/**
 * @brief Ethernet packet header parser with filtering and timestamping
 * 
 * This module implements a packet parser that:
 * 1. Extracts and validates Ethernet/IP/UDP headers
 * 2. Filters packets based on configurable rules
 * 3. Provides packet timing information
 * 4. Streams UDP payload data with AXI-Stream protocol
 * 
 * The module uses a multi-stage pipeline for efficient processing:
 * - Stage 1: Initial packet reception and buffering
 * - Stage 2: Header validation and filtering
 * - Stage 3: FIFO buffering for flow control
 * - Stage 4: Payload streaming
 */
module header_parser (
    // Clock and reset signals
    input  logic         clk,        // System clock
    input  logic         rst_n,      // Active-low asynchronous reset

    // AXI-Stream input interface (LSB-first notation)
    input  logic  [0:255]  in_data,  // Input data bus
    input  logic  [31:0]   in_keep,  // Byte enable mask
    input  logic           in_valid, // Data valid signal
    input  logic           in_last,  // Last word of packet

    // AXI-Stream output interface (LSB-first notation)
    output logic  [0:255]  out_data, // Output data bus
    output logic  [0:31]   out_keep, // Byte enable mask
    output logic           out_valid,// Data valid signal
    output logic           out_last, // Last word of packet

    // Timing interface
    output logic           timestamp_valid,  // Valid timing information
    output logic  [31:0]   timestamp,       // Packet processing time in cycles

    // Flow control
    input  logic           out_ready,       // Downstream ready signal
    output logic           in_ready         // Upstream ready signal
);
    // Constants
    localparam [5:0] HEADER_SIZE = 42-32;   // Header size in bytes

    // State machine definition
    typedef enum logic[1:0] {
        IDLE,           // Waiting for new packet
        PARSE_HEADER,   // Processing packet header
        STREAM_PAYLOAD  // Streaming packet payload
    } parse_state;

    // State variables for pipeline stages
    parse_state state, state_filter, state_fifo, state_output;
    
    // Packet buffer for header analysis
    logic [0:511] packet_buffer;    // LSB-first notation for AXI Stream
    logic         buffer_valid;     // Buffer contains valid data

    // Timing signals
    logic [31:0]  cycle_count;              // Current cycle count
    logic [31:0]  packet_start_timestamp;   // Packet arrival timestamp

    // Cycle counter for timing measurements
    cycle_counter timestamper(.clk, .rst_n, .cycle_count);

    // FIFO interface signals
    logic         fifo_wr_en, fifo_rd_en, fifo_full, fifo_empty;
    logic         bypass_fifo, fifo_valid;
    logic [0:255] stream_data, fifo_data, choice_data;  // LSB-first notation
    logic [0:31]  stream_keep, fifo_keep, choice_keep;  // LSB-first notation
    logic         stream_last, fifo_last;
    logic         stream_valid, bypass_valid, choice_valid, choice_last;
	 
    // Filter interface signals
    logic        filters_valid, header_valid;
    logic        cfg_we;
    logic [3:0]  cfg_waddr, cfg_raddr;
    logic [31:0] cfg_wdata, cfg_rdata;

    // Pipeline registers
    // Special declaration for forced unpacking
    (* preserve, noprune *) logic in_valid_d1;
	 
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            in_valid_d1 <= 1'b0;
        else
            in_valid_d1 <= in_valid;
    end
	
    // Pipeline stage registers
    logic in_valid_d2, in_valid_d3, stream_valid_d1;
    logic [0:255] in_data_d1,  in_data_d2,  in_data_d3, stream_data_d1;
    logic [31:0]  in_keep_d1,  in_keep_d2,  in_keep_d3, stream_keep_d1;
    logic         in_last_d1,  in_last_d2,  in_last_d3, stream_last_d1;
    logic bypass_fifo_d1;

    logic [1:0]   state_d1, state_d2;

    logic [31:0]  packet_start_timestamp_d1, packet_start_timestamp_d2, packet_start_timestamp_d3;

    // Pipeline header validation signal
    logic header_valid_d1;  // Used in final logic/output

    // Main pipeline register block
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            // Reset all pipeline registers
            in_valid_d2 <= 1'b0; in_valid_d3 <= 1'b0;
            in_data_d1  <= '0;   in_data_d2  <= '0;   in_data_d3  <= '0;
            in_keep_d1  <= '0;   in_keep_d2  <= '0;   in_keep_d3  <= '0;
            in_last_d1  <= 1'b0; in_last_d2  <= 1'b0; in_last_d3  <= 1'b0;

            stream_data_d1  <= '0;
            stream_keep_d1  <= '0;
            stream_valid_d1 <= 1'b0;
            stream_last_d1  <= 1'b0;

            state_d1 <= IDLE; state_d2 <= IDLE;

            packet_start_timestamp_d1 <= '0;
            packet_start_timestamp_d2 <= '0;
            packet_start_timestamp_d3 <= '0;

            header_valid_d1 <= 1'b0;
        end else begin
            // Stage 1: Initial reception
            in_data_d1  <= in_data;
            in_keep_d1  <= in_keep;
            in_last_d1  <= in_last;
            state_d1    <= state;
            packet_start_timestamp_d1 <= packet_start_timestamp;

            // Stage 2: Header processing
            in_valid_d2 <= in_valid_d1;
            in_data_d2  <= in_data_d1;
            in_keep_d2  <= in_keep_d1;
            in_last_d2  <= in_last_d1;
            state_d2    <= state_d1;
            packet_start_timestamp_d2 <= packet_start_timestamp_d1;

            // Stage 3: FIFO stage
            in_valid_d3 <= in_valid_d2;
            in_data_d3  <= in_data_d2;
            in_keep_d3  <= in_keep_d2;
            in_last_d3  <= in_last_d2;
            packet_start_timestamp_d3 <= packet_start_timestamp_d2;
            
            header_valid_d1 <= header_valid;  
            bypass_fifo_d1 <= bypass_fifo;

            // Stage 4: Output stage
            stream_data_d1  <= stream_data;
            stream_keep_d1  <= stream_keep;
            stream_valid_d1 <= stream_valid;
            stream_last_d1  <= stream_last;
        end
    end
	 
    // FIFO instantiation for flow control
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

    // FIFO control logic
    assign bypass_fifo = in_valid_d3 && out_ready && fifo_empty;
    assign fifo_valid  = ~fifo_empty;

    // Output multiplexing
    assign out_data  = bypass_fifo_d1 ? stream_data_d1 : fifo_data;
    assign out_keep  = bypass_fifo_d1 ? stream_keep_d1 : fifo_keep;
    assign out_last  = bypass_fifo_d1 ? stream_last_d1 : fifo_last;
    assign out_valid = bypass_fifo_d1 ? stream_valid_d1 : fifo_valid;

    // Flow control
    assign in_ready  = bypass_fifo ? out_ready : !fifo_full;
    assign fifo_wr_en = ~bypass_fifo && stream_valid;
    assign fifo_rd_en = out_ready && fifo_valid && ~bypass_fifo;

    // Filter core instantiation
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

    // Header validation logic
    // Drop malformed packets (last signal in header stage)
    assign header_valid = filters_valid && buffer_valid && ~in_last_d1;

    // Main state machine
    always_ff @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            state                  <= IDLE;
            packet_start_timestamp <= 32'b0;
            timestamp_valid        <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    timestamp_valid <= 1'b0;
                    // Check for valid packet start
                    // Note: Design assumes minimum packet size of 32 bytes
                    if(in_valid_d1 && (&in_keep_d1) && ~in_last_d1) begin
                        packet_start_timestamp <= cycle_count;
                        state                  <= PARSE_HEADER;
                    end 
                end
                PARSE_HEADER: begin
                    if(header_valid) begin
                        // Valid header found, proceed to payload
                        state <= STREAM_PAYLOAD;
                    end else begin
                        // Invalid header, return to idle
                        state <= IDLE;
                    end
                end
                STREAM_PAYLOAD: begin
                    if(in_last_d1) begin
                        // Packet complete, calculate timing
                        state           <= IDLE;
                        timestamp_valid <= 1'b1;
                        timestamp       <= (cycle_count + 1) - packet_start_timestamp;
                    end
                end
            endcase
        end
    end
	 
    // Keep signal processing
    logic keep_contiguous, keep_contiguous_d1, keep_trailing_ones, keep_trailing_ones_d1;
	 
    assign keep_trailing_ones = &in_keep_d1;
	 
    always_ff @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            keep_contiguous_d1 <= 0;
            keep_trailing_ones_d1 <= 0;
        end else begin
            keep_contiguous_d1 <= keep_contiguous;
            keep_trailing_ones_d1 <= keep_trailing_ones;
        end
    end
	 
    // Buffer control
    assign buffer_valid = in_valid_d1 && in_valid_d2 && keep_trailing_ones_d1;
    assign packet_buffer[0:255] = in_data_d1;
    assign packet_buffer[256:511] = in_data_d2;

    // Payload streaming logic
    always_comb begin
        case (state_d1) 
            PARSE_HEADER: begin
                if(header_valid) begin
                    // Pass complete packet data
                    stream_data  = in_data_d3;
                    // Mask out header bytes while preserving keep signal
                    stream_keep  = 32'h00_00_03_FF & in_keep_d3;
                    stream_valid = in_valid_d3;
                    stream_last  = 1'b0;
                end
            end
            STREAM_PAYLOAD: begin
                stream_data            = in_data_d3;
                stream_keep            = in_keep_d3;
                stream_valid           = in_valid_d3;
                stream_last            = in_last_d3;
            end
            default: begin
                stream_data            = 256'b0;
                stream_keep            = 32'b0;
                stream_valid           = 1'b0;
                stream_last            = 1'b0;
            end
        endcase
    end
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
        , 8'hCA,8'hcE,8'hD2,8'hAD,8'hBE,8'hE5  // dest MAC (Wrong)
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
	 
	 
		/*
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

		*/


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


endmodule

