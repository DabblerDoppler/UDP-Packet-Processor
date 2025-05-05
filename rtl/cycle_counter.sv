//simple module that counts clock cycles for the purpose of timestamping.
module cycle_counter ( 
    input logic clk, rst_n,
    output logic [31:0] cycle_count
);
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) cycle_count <= 0;
        else cycle_count <= cycle_count + 1;
    end
endmodule