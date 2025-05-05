//This is a memory-mapped IO interface that uses a simplified 
//AXI-Lite style interface to set filtering rules.
module filter_config (
    input  logic        clk,
    input  logic        rst_n,

    // Simplified AXI sytle configuration interface
    // This simplified version is mostly for testing, 
    // I might update it later to be configurable for use with a CPU.
    input  logic        cfg_we,
    input  logic [3:0]  cfg_waddr,
    input  logic [31:0] cfg_wdata,
    input  logic [3:0]  cfg_raddr,
    output logic [31:0] cfg_rdata,

    // Outputs to match logic
    output logic [47:0] local_mac,
    output logic [15:0] ethertype,
    output logic [7:0]  ip_protocol,
    output logic [31:0] ip_base,
    output logic [31:0] ip_mask,
    output logic [15:0] udp_dst_port
);
    // MAC address is split across two registers
    logic [31:0] mac_lo, mac_hi;

    // Write logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mac_lo         <= 32'hDEADBEEF;
            mac_hi         <= 16'hCAFE;
            ethertype      <= 16'h0800;
            ip_protocol    <= 8'h11;
            ip_base        <= 32'h0A000100;
            ip_mask        <= 32'hFFFFFFFC;
            udp_dst_port   <= 16'd25565;;
        end else if (cfg_we) begin
            case (cfg_waddr)
                4'h0: mac_lo         <= cfg_wdata;
                4'h1: mac_hi         <= cfg_wdata[15:0];
                4'h2: ethertype      <= cfg_wdata[15:0];
                4'h3: ip_protocol    <= cfg_wdata[7:0];
                4'h4: ip_base        <= cfg_wdata;
                4'h5: ip_mask        <= cfg_wdata;
                4'h6: udp_dst_port   <= cfg_wdata[15:0];
                default: ;
            endcase
        end
    end

    // Read logic
    always_comb begin
        case (cfg_raddr)
            4'h0: cfg_rdata = mac_lo;
            4'h1: cfg_rdata = {16'h0, mac_hi};
            4'h2: cfg_rdata = {16'h0, ethertype};
            4'h3: cfg_rdata = {24'h0, ip_protocol};
            4'h4: cfg_rdata = ip_base;
            4'h5: cfg_rdata = ip_mask;
            4'h6: cfg_rdata = {16'h0, udp_dst_port};
            default: cfg_rdata = 32'hDEADBEEF;
        endcase
    end

    // Combine MAC output
    assign local_mac = {mac_hi, mac_lo};

endmodule