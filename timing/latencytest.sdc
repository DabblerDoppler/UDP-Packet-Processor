# Create clock (adjust frequency as needed)
create_clock -period 2.7 -name clk [get_ports clk]

# Input and output delays
set_input_delay -clock clk -max 1.0 [get_ports {in_data[*] in_keep[*] in_valid in_last}]
set_output_delay -clock clk -max 1.0 [get_ports {out_data[*] out_keep[*] out_valid out_last}]

# False paths (if applicable)
set_false_path -from [get_ports rst_n]
set_false_path -from [get_ports out_ready]

set_multicycle_path 1 -from [get_ports clk]