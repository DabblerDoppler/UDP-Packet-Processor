onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider Global
add wave -noupdate -radix hexadecimal /header_parser_testbench/clk
add wave -noupdate -radix hexadecimal /header_parser_testbench/rst_n
add wave -noupdate -divider {AXI Input}
add wave -noupdate -radix hexadecimal /header_parser_testbench/in_data
add wave -noupdate -radix hexadecimal /header_parser_testbench/in_keep
add wave -noupdate -radix binary /header_parser_testbench/in_valid
add wave -noupdate -radix binary /header_parser_testbench/in_last
add wave -noupdate -radix binary /header_parser_testbench/in_ready
add wave -noupdate /header_parser_testbench/dut/in_keep_d1
add wave -noupdate /header_parser_testbench/dut/in_valid_d1
add wave -noupdate /header_parser_testbench/dut/in_last_d1
add wave -noupdate /header_parser_testbench/dut/in_keep_d2
add wave -noupdate /header_parser_testbench/dut/in_valid_d2
add wave -noupdate /header_parser_testbench/dut/in_last_d2
add wave -noupdate -divider {AXI Output}
add wave -noupdate -radix hexadecimal /header_parser_testbench/out_data
add wave -noupdate -radix hexadecimal /header_parser_testbench/out_keep
add wave -noupdate -radix binary /header_parser_testbench/out_valid
add wave -noupdate -radix binary /header_parser_testbench/out_last
add wave -noupdate -radix unsigned /header_parser_testbench/timestamp
add wave -noupdate /header_parser_testbench/dut/timestamp_valid
add wave -noupdate -radix binary /header_parser_testbench/out_ready
add wave -noupdate -divider {DUT Internals}
add wave -noupdate -radix unsigned /header_parser_testbench/dut/state
add wave -noupdate -radix unsigned /header_parser_testbench/dut/cycle_count
add wave -noupdate -radix unsigned /header_parser_testbench/dut/packet_start_timestamp
add wave -noupdate -radix binary /header_parser_testbench/dut/buffer_valid
add wave -noupdate -radix binary /header_parser_testbench/dut/header_valid
add wave -noupdate -radix binary /header_parser_testbench/dut/filters_valid
add wave -noupdate -divider {Filter Internals}
add wave -noupdate /header_parser_testbench/dut/my_filter_core/eth_valid
add wave -noupdate /header_parser_testbench/dut/my_filter_core/ip_valid
add wave -noupdate /header_parser_testbench/dut/my_filter_core/udp_valid
add wave -noupdate -radix hexadecimal /header_parser_testbench/dut/my_filter_core/cfg_local_mac
add wave -noupdate -radix hexadecimal /header_parser_testbench/dut/my_filter_core/cfg_ethertype
add wave -noupdate -radix hexadecimal /header_parser_testbench/dut/my_filter_core/cfg_ip_protocol
add wave -noupdate -radix hexadecimal /header_parser_testbench/dut/my_filter_core/cfg_ip_base
add wave -noupdate -radix hexadecimal /header_parser_testbench/dut/my_filter_core/cfg_ip_mask
add wave -noupdate -radix hexadecimal /header_parser_testbench/dut/my_filter_core/cfg_dest_port
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {216 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 318
configure wave -valuecolwidth 115
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 50
configure wave -gridperiod 1
configure wave -griddelta 80
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ps} {276 ps}
