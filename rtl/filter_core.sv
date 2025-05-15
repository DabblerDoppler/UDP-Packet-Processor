/**
 * @brief Configurable packet filtering module for Ethernet/IP/UDP packets
 * 
 * This module implements a combinational filter that validates packets based on
 * multiple criteria across different protocol layers:
 * - Ethernet: Local MAC address and EtherType
 * - IP: Destination IP address (with configurable subnet mask) and protocol
 * - UDP: Destination port number
 * 
 * The module uses a memory-mapped configuration interface to dynamically update
 * filtering rules during operation.
 */
module filter_core(
    // Clock and reset signals
    input  logic        clk,        // System clock
    input  logic        rst_n,      // Active-low asynchronous reset
    
    // Packet data input (512-bit wide for header analysis)
    input  logic [0:511] data,      // Packet data in LSB-first format

    // Configuration interface (AXI-Lite style)
    input  logic        cfg_we,     // Write enable signal
    input  logic [3:0]  cfg_waddr,  // Write address (4-bit address space)
    input  logic [31:0] cfg_wdata,  // Write data (32-bit data bus)
    input  logic [3:0]  cfg_raddr,  // Read address (4-bit address space)
    output logic [31:0] cfg_rdata,  // Read data (32-bit data bus)

    // Filter validation output
    output logic        filters_valid  // High when all filter criteria are met
);

    // Protocol constants
    localparam IP_VERSION = 4;      // IPv4 protocol version
    // Minimum IP header length in 32-bit words (5 words = 20 bytes)
    localparam HEADER_LENGTH = 5;   // Standard IPv4 header length
    
    // Internal validation signals for each protocol layer
    logic        eth_valid, ip_valid, udp_valid;
    
    // Configuration signals from filter_config module
    logic [47:0] cfg_local_mac;     // Local MAC address to match
    logic [15:0] cfg_ethertype;     // EtherType to match (e.g., 0x0800 for IPv4)
    logic [7:0]  cfg_ip_protocol;   // IP protocol number (e.g., 0x11 for UDP)
    logic [31:0] cfg_ip_base;       // Base IP address for range matching
    logic [31:0] cfg_ip_mask;       // IP address mask for subnet matching
    logic [15:0] cfg_dest_port;     // UDP destination port to match

    // Instantiate configuration module for filter rules
    filter_config my_configuration (
        .clk, 
        .rst_n, 
        .cfg_we, 
        .cfg_waddr, 
        .cfg_wdata, 
        .cfg_raddr, 
        .cfg_rdata, 
        .local_mac(cfg_local_mac), 
        .ethertype(cfg_ethertype), 
        .ip_protocol(cfg_ip_protocol), 
        .ip_base(cfg_ip_base), 
        .ip_mask(cfg_ip_mask), 
        .udp_dst_port(cfg_dest_port)
    );

    // Ethernet header validation
    // Check destination MAC address and EtherType
    assign eth_valid = (data[464:479]  == cfg_local_mac[47:32] && // Upper MAC bytes
                        data[400:415] == cfg_ethertype);        // EtherType field
						
    // IPv4 header validation (bytes 14-33)
    // Check version, header length, protocol, and destination IP
    assign ip_valid = data[396:399] == IP_VERSION &&           // IP version (4)
                      data[392:395] == HEADER_LENGTH &&        // Header length (5)
                      data[320:327] == cfg_ip_protocol &&      // Protocol (UDP)
                      (data[240:271] & cfg_ip_mask) == cfg_ip_base;  // IP address match

    // UDP header validation
    // Check destination port number
    assign udp_valid = (data[208:223] == cfg_dest_port);

    // Final validation: all protocol layers must pass
    assign filters_valid = (eth_valid && ip_valid && udp_valid);
        
endmodule