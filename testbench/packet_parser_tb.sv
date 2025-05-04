module packet_parser_tb;

    logic clk, rst_n;
    logic [7:0] in_data;
    logic in_valid, in_last;
    logic [7:0] out_data;
    logic out_valid, out_last;

    packet_parser dut (
        .clk, .rst_n,
        .in_data, .in_valid, .in_last,
        .out_data, .out_valid, .out_last
    );

    // Clock
    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst_n = 0;
        in_data = 0;
        in_valid = 0;
        in_last = 0;
        #20 rst_n = 1;

        // TODO: Drive example packet
    end

endmodule