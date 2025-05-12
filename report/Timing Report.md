**AXI-Stream Header Parser Timing Optimization Report**

**Overview**  
This document outlines the challenges, methodologies, and results of timing optimization for a 256-bit AXI-Stream header parser implemented on Intel's Arria 10 FPGA. The project was developed as a resume portfolio item, with the intent of demonstrating deep understanding of pipelining, timing closure, floorplanning, and synthesis control relevant to high-frequency trading (HFT) hardware applications.

---

**Design Summary**
- **Target Platform**: Intel Arria 10
- **Input Interface**: AXI-Stream, 256-bit width, LSB-first
- **Pipeline Depth**: 4 stages
- **Functional Goal**: Parse Ethernet/IP/UDP headers and timestamp incoming packets
- **Target FMax**: 350 MHz aspirational, >250 MHz required
- **Achieved FMax**: 251 MHz

---

**Challenges Encountered**

1. **Slow Critical Paths from IO Buffers**
   - Initial worst-case paths were from `in_valid` and `in_keep` IO buffers to their first pipeline registers (`*_d1`), with delays exceeding 7.5 ns due to long interconnect (IC) and poor placement.
   - Placement was unconstrained, resulting in registers landing far from their IO buffers.

2. **Timing Analysis Failures on Virtual Outputs**
   - Output pins (e.g., `out_valid`) were showing up as critical paths in reports, despite not being relevant to internal pipeline timing.
   - Attempts to apply `set_output_delay 0` were partially ineffective.

3. **FSM and Header Alignment Issues**
   - The FSM used for packet parsing depended on `header_valid`, which was generated 2 pipeline stages later, causing timing and alignment ambiguity.
   - Pipeline synchronization between FSM logic and downstream `stream_*` signals required careful staging and realignment.

4. **Seed Variability**
   - Significant FMax variation across seeds. Seed 1 could yield 200 MHz, while seed 4 reached 251 MHz.
   - Needed a way to programmatically identify and reuse the best seed.

5. **Quartus Scripting Limitations**
   - `--export_assignments` was unavailable in Quartus Standard.
   - `get_report_panel_data` initially failed due to missing `Timing Analyzer Summary` panel, stemming from SDC omissions.

---

**Solutions Implemented**

1. **Manual IO + Register Placement with LogicLock**
   - Identified active IO buffer regions in Chip Planner (Y-coordinates 33, 61, 88, 115, 142, 169, 196 on column 141).
   - Wrote TCL scripts to align `in_data[*]`, `in_keep[*]`, `in_valid`, and `in_last` to those IO buffer rows.
   - Placed corresponding `_d1` registers in columns 139–140 to minimize IC delays.

2. **Pipeline Registering and Forwarding Cleanup**
   - Ensured all FSM-related signals were staged 2–3 cycles to match header validation timing.
   - Refactored combinational blocks to read from `*_d1/d2/d3` versions of all timing-sensitive signals.

3. **Quartus Tcl Automation and Seed Sweeping**
   - Created a `sweep_seeds_and_lock.tcl` script to run `quartus_map`, `quartus_fit`, `quartus_sta` for N seeds.
   - Automatically parsed slack using a generated `get_slack_temp.tcl` that opened the project and extracted slack from STA reports.
   - Once the best seed was found, regenerated placement and applied `PLACEMENT_LOCK ON` for each instance.

4. **Placement Lock Export Fixes**
   - Replaced `--export_assignments` with a `quartus_cdb -t` call to a generated `export_placement.tcl`:
     ```tcl
     project_open header_parser -revision header_parser
     write_assignment_file -file best_seed_placement.qsf
     project_close
     ```

5. **Slack Panel Fallback and Debugging**
   - Enhanced script to dump available report panels.
   - Fallback to safer slack extraction logic with warnings if `Timing Analyzer Summary` not found.

6. **Resume Optimization and Labeling**
   - Final synthesis performance: **251 MHz @ 256-bit datapath (~64.3 Gbps)**
   - Best seed locked into `header_parser.qsf` using:
     ```tcl
     set_global_assignment -name FITTER_SEED 4
     source best_seed_placement.qsf
     ```

---

**Attempted Manual Optimization in Quartus Standard**

In an effort to further refine placement and squeeze out additional MHz, manual locking was attempted using Chip Planner and Tcl scripting. However, Quartus Standard presents several roadblocks:

- Chip Planner lacks full support for exporting netlist-based placement data
- Tcl commands like `get_nodes`, `get_node_info`, and `get_names` vary between GUI, CLI, and Chip Planner contexts, often producing errors or empty results
- LogicLock regions in Standard Edition do not enforce fixed placement without additional per-instance `PLACEMENT_LOCK` commands
- Post-fit netlist interaction is limited; verifying true register placement programmatically is cumbersome

Ultimately, the project encountered diminishing returns from further hand-optimization due to these tool limitations. Quartus Standard is not designed for fine-grained physical tuning, and a Pro license would be required for more advanced floorplanning, automated region locking, or fitter-guided placement optimization.

---

**Next Steps / Optional Enhancements**
- Export slack and seed per run to CSV
- Add hierarchical LogicLock regions for larger designs
- Improve latency modeling for timestamping accuracy
- Push for >300 MHz by hand-placing critical pipeline paths

---

**Conclusion**  
This project demonstrates the full optimization loop of a high-performance packet processing module, from RTL through fitter timing closure. It showcases an understanding of pipelining, synchronization, floorplanning, slack debugging, Quartus scripting, and build reproducibility — all of which are relevant for timing-critical FPGA applications such as HFT.
