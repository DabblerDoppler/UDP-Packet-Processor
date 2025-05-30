# Create clock (adjust frequency as needed)
create_clock -period 4.0 -name clk [get_ports clk]

# Input and output delays
set_input_delay -clock clk -max 1.0 [get_ports {in_data[*] in_keep[*] in_valid in_last}]
set_output_delay -clock clk -max 0.0 [get_ports {out_data[*] out_keep[*] out_valid out_last}]

# False paths (if applicable)
set_false_path -from [get_ports rst_n]
set_false_path -from [get_ports out_ready]

set_false_path -to [get_ports out_valid]
set_false_path -to [get_ports out_keep[*]]
set_false_path -to [get_ports out_data[*]]
set_false_path -to [get_ports out_last]