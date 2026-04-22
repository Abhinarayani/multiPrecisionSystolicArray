#!/usr/bin/env tclsh
# Compile and run UART testbench

# Load project
puts "Opening project 751..."
source 751.cr.mti

# Compile all files
puts "Compiling RTL files..."
vlog rtl/bitsys_pkg.sv
vlog rtl/bitsys_systolic_array.sv
vlog rtl/uart_rx.sv
vlog rtl/uart_tx.sv
vlog rtl/bitsys_uart_top.sv

puts "Compiling testbench..."
vlog tb/tb_uart_design.sv

puts "Starting simulation..."
vsim -c work.tb_uart_design -do "run -all; quit"
