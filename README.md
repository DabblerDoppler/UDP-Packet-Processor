# UDP Packet Processor

A high-performance UDP header parser using a 256-bit AXI input stream. Designed for low latency as a resume project for High-Frequency Trading (HFT) applications.

## Project Goals

- Explore placement-aware pipelining and high-speed I/O constraints
- Demonstrate competence in:
  - SystemVerilog RTL design
  - Timing analysis and STA debugging
  - Tcl scripting in Quartus
  - Manual and automated floorplanning
  - Performance tuning for HFT-class systems

## Features

- 256-bit AXI-style stream interface
- Low-latency packet processing
- Configurable packet filtering
- Backpressure functionality
- Optimized for Arria 10 implementation

## Architecture

![Architecture Diagram](report/images/architecture.png)

The UDP Packet Processor consists of the following key components:
- Header Parser
- Packet Filter
- Output FIFO

## Performance Metrics

| Metric | Value |
|--------|-------|
| Maximum Clock Frequency (Slow 900mV 100C Model) | 251 MHz |
| Latency | 4 clock cycles, ~15.9 ns  |
| Resource Utilization | X LUTs, X FFs, X BRAMs |
| Throughput | ~64.3 Gbps |

## Simulation and Verification

The design has been verified using:
- Integration tests for the complete system
- Directed test cases for edge conditions

Full verification was not a priority for this project. I intend for my next project to focus on UVM methodologies, and I wanted to hone in on timing for this one.


## License

This project is licensed under the MIT License - see the LICENSE file for details.
```
