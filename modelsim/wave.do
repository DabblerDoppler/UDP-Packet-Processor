add wave -divider "Global"
add wave -hex clk
add wave -hex rst_n

add wave -divider "AXI Input"
add wave -hex in_data
add wave -hex in_keep
add wave -bin in_valid
add wave -bin in_last
add wave -bin in_ready

add wave -divider "AXI Output"
add wave -hex out_data
add wave -hex out_keep
add wave -bin out_valid
add wave -bin out_last
add wave -hex timestamp
add wave -bin out_ready

add wave -divider "DUT Internals"
add wave -radix unsigned dut.state
add wave -hex dut.packet_buffer
add wave -dec dut.valid_bytes
add wave -bin dut.buffer_valid
add wave -bin dut.prev_buffer_valid
add wave -hex dut.cycle_count
add wave -hex dut.packet_start_timestamp
add wave -bin dut.header_valid
add wave -bin dut.filters_valid

update