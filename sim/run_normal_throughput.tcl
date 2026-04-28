vlib work

vlog -sv rtl/bitsys_pkg.sv
vlog -sv rtl/normal_mac.sv
vlog -sv rtl/normal_systolic_array.sv
vlog -sv tb/tb_normal_throughput.sv

vsim -c work.tb_normal_throughput -do "run -all; quit -f"
