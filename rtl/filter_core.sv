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
    logic [47:0] cfg_local_mac;
    logic [15:0] cfg_ethertype;

    logic [7:0]  cfg_ip_protocol;
    logic [31:0] cfg_ip_base, cfg_ip_mask;

    logic [15:0] cfg_dest_port;

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

    
    assign eth_valid = (data[464:479]  == cfg_local_mac[47:32] && // partial matching for validation
                        data[400:415] == cfg_ethertype);        // bytes 12-13
						
								
	 
    
    // IPv4 header (bytes 14–33)
    assign ip_valid = data[396:399] == IP_VERSION && 
                      data[392:395] == HEADER_LENGTH && 
                      data[320:327] == cfg_ip_protocol && 
                      (data[240:271] & cfg_ip_mask) == cfg_ip_base;
    

    assign udp_valid = (data[208:223] == cfg_dest_port);

    // Overall, the data is valid only if all our filters validate it.
    assign filters_valid = (eth_valid && ip_valid && udp_valid);
        
endmodule