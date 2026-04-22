# DE1-SoC Quartus Project Setup Script (Quartus 24.1)
# Cyclone V FPGA
# Run this from the project root directory:
# quartus_sh -t quartus/setup_project.tcl

# Create new project
project_new -overwrite bitsys_de1 -family "Cyclone V" -device 5CSEMA5F31C6

# Set top-level entity
set_global_assignment -name TOP_LEVEL_ENTITY bitsys_uart_top

# Add all source files (in dependency order)
set_global_assignment -name SYSTEMVERILOG_FILE rtl/bitsys_pkg.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/bitsys_pe_t1.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/bitsys_pe_t2.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/bitsys_mul.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/bitsys_accu_conv.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/bitsys_mac.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/bitsys_clock_gate.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/bitsys_systolic_array.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/uart_rx.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/uart_tx.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/bitsys_uart_top.sv

# Synthesis settings
set_global_assignment -name SYNTH_GATED_CLOCK_CONVERSION OFF
set_global_assignment -name NUM_PARALLEL_PROCESSORS 4

# Pin assignments - DE1-SoC
# Clock (50 MHz)
set_location_assignment PIN_AF14 -to clk
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk

# Reset button (KEY0, active low)
set_location_assignment PIN_AE9 -to rst_n
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to rst_n

# UART - DE1-SoC HPS UART pins (from manual)
# RX: HPS_UART_RX
set_location_assignment PIN_B25 -to rx
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to rx

# TX: HPS_UART_TX
set_location_assignment PIN_C25 -to tx
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to tx

# Precision and signed mode - using floating (fitter will assign to available pins)
# These are optional control signals, not critical for basic operation
# Uncomment and assign to valid GPIO pins if needed
