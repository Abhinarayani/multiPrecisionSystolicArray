#!/usr/bin/env quartus_sh
# Platform Designer (Qsys) script to create HPS system with UART routed to FPGA fabric
# Usage: quartus_sh -t create_hps_system.tcl

set script_dir [file dirname [info script]]

# Create new Qsys system
create_system -name hps_system -dir $script_dir -hdl VERILOG

# Set device and other properties
set_project_property DEVICE {5CSEMA5F31C6}
set_project_property DEVICE_FAMILY {Cyclone V}
set_project_property HIDE_FROM_IP_CATALOG {false}

# Add Cyclone V HPS (Hard Processor System)
add_instance hps altera_hps
set_instance_property hps AUTO_EXPORT_SLAVE_MODULES {true}

# ─── Configure HPS UART to use FPGA pins ───
# This routes HPS UART signals to the FPGA fabric instead of dedicated HPS pins
set_instance_parameter_value hps {UART0_MODE} {FPGA}

# Add clock input (from FPGA)
add_instance clk_0 clock_source
set_instance_property clk_0 clockFrequency {50000000}
add_connection clk_0.clk hps.clk_reset_clk
add_connection clk_0.clk_reset hps.clk_reset_reset

# Add reset input (from FPGA, active low)
add_instance reset_0 altera_reset_controller
set_instance_property reset_0 OUTPUT_ASSERTION_TYPE {active_low}
set_instance_property reset_0 SYNCHRONOUS_EDGES {deassert}
add_connection clk_0.clk reset_0.clk
add_connection reset_0.reset_out hps.clk_reset_reset_req

# Export HPS signals for external connection
export hps.hps_io hps_io

# Export FPGA-routed UART signals
export hps.uart0_cts uart_cts
export hps.uart0_rts uart_rts
export hps.uart0_rx uart_rx
export hps.uart0_tx uart_tx

# Save and generate
save_system hps_system.qsys
generate_system -synthesis VERILOG
