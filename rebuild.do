#!/bin/bash
# Force fresh compilation

# Try to kill any running simulations
quit -sim

# Clean and recompile all RTL
vdel -all -lib work

# Recompile RTL files
vlog rtl/bitsys_pkg.sv
vlog rtl/bitsys_systolic_array.sv
vlog rtl/uart_rx.sv
vlog rtl/uart_tx.sv
vlog rtl/bitsys_uart_top.sv

# Recompile testbench
vlog tb/tb_uart_design.sv

# Start fresh simulation
vsim -c work.tb_uart_design -do "run -all"
