vlib work
vlog -sv ../rtl/cycle_counter.sv
vlog -sv ../rtl/fifo.sv
vlog -sv ../rtl/filter_config.sv
vlog -sv ../rtl/filter_core.sv
vlog -sv ../rtl/header_parser.sv

vsim -voptargs=+acc work.header_parser_testbench

do wave.do
run -all