lappend search_path "../rtl"

analyze -library work -format sverilog \
 {../rtl/bitsys_pkg.sv \
	 ../rtl/bitsys_systolic_array.sv \
	 ../rtl/bitsys_pe_t1.sv \
	 ../rtl/bitsys_pe_t2.sv \
	 ../rtl/bitsys_mac.sv \
	 ../rtl/bitsys_mul.sv \
	 ../rtl/bitsys_accu_conv.sv \
	 ../rtl/bitsys_clock_gate.sv
}
