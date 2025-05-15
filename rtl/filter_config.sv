/**
 * @brief Configuration module for Ethernet packet filtering rules
 * 
 * This module implements a memory-mapped configuration interface using a simplified
 * AXI-Lite style protocol. It allows dynamic configuration of packet filtering
 * parameters including MAC address, EtherType, IP protocol, IP address range,
 * and UDP destination port.
 */
module filter_config (
    // Clock and reset signals
    input  logic        clk,        // System clock
    input  logic        rst_n,      // Active-low asynchronous reset

    // Configuration interface (AXI-Lite style)
    input  logic        cfg_we,     // Write enable signal
    input  logic [3:0]  cfg_waddr,  // Write address (4-bit address space)
    input  logic [31:0] cfg_wdata,  // Write data (32-bit data bus)
    input  logic [3:0]  cfg_raddr,  // Read address (4-bit address space)
    output logic [31:0] cfg_rdata,  // Read data (32-bit data bus)

    // Filter configuration outputs
    output logic [47:0] local_mac,      // Local MAC address for filtering
    output logic [15:0] ethertype,      // EtherType to match (e.g., 0x0800 for IPv4)
    output logic [7:0]  ip_protocol,    // IP protocol number (e.g., 0x11 for UDP)
    output logic [31:0] ip_base,        // Base IP address for range matching
    output logic [31:0] ip_mask,        // IP address mask for range matching
    output logic [15:0] udp_dst_port    // UDP destination port to match
);
    // Internal registers for MAC address storage
    // MAC address is split across two registers due to 32-bit data bus
    logic [31:0] mac_lo;    // Lower 32 bits of MAC address
    logic [15:0] mac_hi;    // Upper 16 bits of MAC address

    // Write logic: Updates configuration registers on valid write operations
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Default values on reset
            mac_lo         <= 32'hDEADBEEF;  // Default MAC address lower bits
            mac_hi         <= 16'hCAFE;      // Default MAC address upper bits
            ethertype      <= 16'h0800;      // Default to IPv4 EtherType
            ip_protocol    <= 8'h11;         // Default to UDP protocol
            ip_base        <= 32'h0A000100;  // Default IP base address
            ip_mask        <= 32'hFFFFFFFC;  // Default IP mask (30-bit subnet)
            udp_dst_port   <= 16'd25565;     // Default UDP port (Minecraft)
        end else if (cfg_we) begin
            // Write operation based on address
            case (cfg_waddr)
                4'h0: mac_lo         <= cfg_wdata;           // Write MAC address lower bits
                4'h1: mac_hi         <= cfg_wdata[15:0];     // Write MAC address upper bits
                4'h2: ethertype      <= cfg_wdata[15:0];     // Write EtherType
                4'h3: ip_protocol    <= cfg_wdata[7:0];      // Write IP protocol
                4'h4: ip_base        <= cfg_wdata;           // Write IP base address
                4'h5: ip_mask        <= cfg_wdata;           // Write IP mask
                4'h6: udp_dst_port   <= cfg_wdata[15:0];     // Write UDP port
                default: ;                                   // Unused addresses
            endcase
        end
    end

    // Read logic: Provides configuration values based on read address
    always_comb begin
        case (cfg_raddr)
            4'h0: cfg_rdata = mac_lo;                        // Read MAC address lower bits
            4'h1: cfg_rdata = {16'h0, mac_hi};              // Read MAC address upper bits
            4'h2: cfg_rdata = {16'h0, ethertype};           // Read EtherType
            4'h3: cfg_rdata = {24'h0, ip_protocol};         // Read IP protocol
            4'h4: cfg_rdata = ip_base;                      // Read IP base address
            4'h5: cfg_rdata = ip_mask;                      // Read IP mask
            4'h6: cfg_rdata = {16'h0, udp_dst_port};        // Read UDP port
            default: cfg_rdata = 32'hDEADBEEF;              // Invalid address read
        endcase
    end

    // Combine MAC address parts into a single 48-bit output
    assign local_mac = {mac_hi, mac_lo};

endmodule