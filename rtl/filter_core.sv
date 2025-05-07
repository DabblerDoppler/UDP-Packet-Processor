// This is a configurable, combinational filter module which checks the following rules:
// Ethernet: Local MAC, Ethertype
// IP: Destination IP (with configurable mask), protocol
// UDP: Destination Port
module filter_core(
    // The filter's combinational, but the configuration module requires these
    input  logic        clk,
    input  logic        rst_n,
    
    // Header data input
    input  logic [0:511] data,

    // AXI style configuration interface
    input  logic        cfg_we,
    input  logic [3:0]  cfg_waddr,
    input  logic [31:0] cfg_wdata,
    input  logic [3:0]  cfg_raddr,
    output logic [31:0] cfg_rdata,

    output logic        filters_valid
);

    localparam IP_VERSION = 4;
    // The desired header length is 20 or greater, but we multiply
    // ip_header_length by 4, so it's really 5 or greater.
    localparam HEADER_LENGTH = 5;
    
    logic        eth_valid, ip_valid, udp_valid;
    logic [47:0] dest_mac, source_mac, cfg_local_mac;
    logic [15:0] ethertype, cfg_ethertype;

    logic [3:0]  ip_version, ip_header_length;
    logic [7:0]  ip_protocol, cfg_ip_protocol;
    logic [31:0] ip_dest, cfg_ip_base, cfg_ip_mask;

    logic [15:0] dest_port, cfg_dest_port;

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

    // Ethernet header (bytes 0–13)
    assign dest_mac   = data[464:511];    // bytes 0–5
    assign source_mac = data[416:463];   // bytes 6–11
    assign ethertype  = data[400:415];  // bytes 12–13
    
    assign eth_valid = (dest_mac  == cfg_local_mac &&
                        ethertype == cfg_ethertype);
    
    // IPv4 header (bytes 14–33)
    assign ip_version = data[396:399]; //half of byte 13
    assign ip_header_length = data[392:395]; 
    assign ip_protocol = data[320:327];
    assign ip_dest = data[240:271];
    
    assign version_correct       = ip_version       == IP_VERSION;
    assign header_length_correct = ip_header_length == HEADER_LENGTH;
    assign protocol_correct      = ip_protocol      == cfg_ip_protocol;
    assign dest_correct          = (ip_dest & cfg_ip_mask) == cfg_ip_base;
    
    assign ip_valid = version_correct && 
                      header_length_correct && 
                      protocol_correct && 
                      dest_correct;
    
    // UDP header (bytes 34–41)
    // Destination port is bytes 36–37
    assign dest_port = data[208:223];

    assign udp_valid = (dest_port == cfg_dest_port);

    // Overall, the data is valid only if all our filters validate it.
    assign filters_valid = (eth_valid && ip_valid && udp_valid);
        
endmodule