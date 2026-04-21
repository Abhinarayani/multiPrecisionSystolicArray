# DE1-SoC Quartus Project Setup Script
# Run this from the project root directory:
# quartus_sh -t setup_project.tcl

# Create new project
project_new -overwrite bitsys_de1 -family "Cyclone V" -device 5CSEMA5F31C6

# Set project source files
set_global_assignment -name TOP_LEVEL_ENTITY bitsys_uart_top
set_global_assignment -name VERILOG_FILE rtl/bitsys_pkg.sv
set_global_assignment -name VERILOG_FILE rtl/bitsys_pe_t1.sv
set_global_assignment -name VERILOG_FILE rtl/bitsys_pe_t2.sv
set_global_assignment -name VERILOG_FILE rtl/bitsys_mul.sv
set_global_assignment -name VERILOG_FILE rtl/bitsys_accu_conv.sv
set_global_assignment -name VERILOG_FILE rtl/bitsys_mac.sv
set_global_assignment -name VERILOG_FILE rtl/bitsys_clock_gate.sv
set_global_assignment -name VERILOG_FILE rtl/bitsys_systolic_array.sv
set_global_assignment -name VERILOG_FILE rtl/uart_rx.sv
set_global_assignment -name VERILOG_FILE rtl/uart_tx.sv
set_global_assignment -name VERILOG_FILE rtl/bitsys_uart_top.sv

# Device settings
set_global_assignment -name DEVICE_FILTER_PACKAGE FBGA
set_global_assignment -name DEVICE_FILTER_PIN_COUNT 896

# Compiler settings
set_global_assignment -name OPTIMIZATION_MODE AGGRESSIVE
set_global_assignment -name FITTER_AGGRESSIVE_ROUTABILITY_OPTIMIZATION ON
set_global_assignment -name PLACEMENT_EFFORT_MULTIPLIER 2

# Synthesis settings
set_global_assignment -name SYNTH_GATED_CLOCK_CONVERSION OFF
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

# Pin assignments - DE1-SoC GPIO/UART
set_global_assignment -name LOCATION_ATTR_USED ON
set_global_assignment -name RESERVE_ALL_UNUSED_PINS "AS INPUT TRI-STATED WITH WEAK PULL-UP"

# DE1-SoC Clock (50 MHz)
set_location_assignment PIN_AF14 -to clk
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk

# Reset button (KEY0, active low)
set_location_assignment PIN_AE9 -to rst_n
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to rst_n

# UART connections via GPIO
# Note: These use GPIO pins. Adjust based on actual pin availability.
# RX: GPIO_0[0] -> PIN_D3
# TX: GPIO_0[1] -> PIN_C3
set_location_assignment PIN_D3 -to rx
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to rx

set_location_assignment PIN_C3 -to tx
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to tx

# Precision mode (via switches or hardcoded, using GPIO_0[2:3])
set_location_assignment PIN_A3 -to prec[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to prec[0]

set_location_assignment PIN_B3 -to prec[1]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to prec[1]

# is_signed (via GPIO_0[4])
set_location_assignment PIN_J3 -to is_signed
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to is_signed

# bnn_mode (via GPIO_0[5])
set_location_assignment PIN_G3 -to bnn_mode
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to bnn_mode

# I/O standard for all other pins
set_global_assignment -name RESERVE_ALL_UNUSED_PINS_WEAK_PULLUP "AS OUTPUT DRIVING AN UNSPECIFIED SIGNAL"

# Commit assignments
export_assignments

puts "Project setup complete!"
puts "Next steps:"
puts "1. Run Analysis & Synthesis: quartus_map bitsys_de1"
puts "2. Run Fitter: quartus_fit bitsys_de1"
puts "3. Run Assembler: quartus_asm bitsys_de1"
puts "4. Program FPGA: quartus_pgm -c USB-Blaster -m JTAG -o \"P;bitsys_de1.sof\""
