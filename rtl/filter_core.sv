//Ethernet constants
const LOCAL_MAC = 48'hDEADBEEFCAFE;
const ETHERTYPE_IPV4 = 16'h0800;

//IP constants
const logic [4:0] UDP_PROTOCOL = 17;
const logic [3:0] IP_VERSION = 4;
//the desired header length is 20 or greater, but we multiply
//ip_header_length by 4, so it's really 5 or greater.
const logic [3:0] HEADER_LENGTH = 5;
const logic [31:0] IP_MASK = 32'hFFFFFFFC;
const logic [31:0] IP_BASE = 32'h0A000100;

//UDP constant
const logic [15:0] DEST_PORT = 25565;


module filter_core(
    input logic [511:0] data,

    output logic filters_valid,
);

    logic eth_valid, ip_valid, udp_valid;

    logic [47:0] dest_mac, source_mac;
    logic [15:0] ethertype;

    logic [3:0] ip_version, ip_header_length;
    logic [7:0] ip_protocol;
    logic [31:0] ip_dest;

    logic [15:0] dest_port;


    assign dest_mac = data[47:0];
    assign source_mac = data[95:48];
    assign ethertype = data[111:96];

    assign ip_version = data[115:112];
    assign ip_header_length = data[119:116];
    assign ip_protocol = data[191:184];
    assign ip_dest = data[255:224];
    
    assign dest_port = data[303:388]


    assign eth_valid =         
            (dest_mac == LOCAL_MAC &&
            ethertype == ETHERTYPE_IPV4);

    assign version_correct = ip_version == IP_VERSION;
    assign header_length_correct == ip_header_length == HEADER_LENGTH;
    assign protocol_correct == ip_protocol == UDP_PROTOCOL;
    //bitwise and the destination and our mask, and compare that to the base.
    assign dest_correct = (ip_dest & IP_MASK) == IP_BASE;

    assign ip_valid = (version_correct && 
                        header_length_correct && 
                        protocol_correct && 
                        dest_correct)

    assign udp_valid = (dest_port == DEST_PORT);

    assign filters_valid = (eth_valid && ip_valid && udp_valid);
        
endmodule