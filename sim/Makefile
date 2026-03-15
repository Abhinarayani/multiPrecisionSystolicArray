# Makefile for BitSys Systolic Array Simulation
# Supports: iverilog (default) or verilator
# Usage:
#   make sim_mul      – simulate the BitSys multiplier testbench
#   make sim_sa       – simulate the full systolic array testbench
#   make all          – run both
#   make waves_mul    – open multiplier VCD in gtkwave
#   make waves_sa     – open systolic array VCD in gtkwave
#   make clean

RTL_DIR  = ../rtl
TB_DIR   = ../tb
SIM_DIR  = .

IV       = iverilog
IFLAGS   = -g2012 -I$(RTL_DIR) -I$(TB_DIR)

# RTL sources (order matters for packages)
RTL_SRCS = $(RTL_DIR)/bitsys_pkg.sv     \
           $(RTL_DIR)/bitsys_pe_t1.sv   \
           $(RTL_DIR)/bitsys_pe_t2.sv   \
           $(RTL_DIR)/bitsys_mul.sv     \
           $(RTL_DIR)/bitsys_accu_conv.sv \
           $(RTL_DIR)/bitsys_mac.sv     \
           $(RTL_DIR)/bitsys_systolic_array.sv

# -----------------------------------------------------------------------
# Multiplier testbench
# -----------------------------------------------------------------------
MUL_TB   = $(TB_DIR)/tb_bitsys_mul.sv
MUL_OUT  = sim_mul

$(MUL_OUT): $(RTL_SRCS) $(MUL_TB)
	$(IV) $(IFLAGS) -o $@ \
	    $(RTL_SRCS) $(MUL_TB)

run_mul: $(MUL_OUT)
	./$(MUL_OUT)

waves_mul: sim_mul_waves.vcd
	gtkwave $< &

sim_mul_waves.vcd: $(MUL_OUT)
	./$(MUL_OUT) +dumpvars

# -----------------------------------------------------------------------
# Systolic Array testbench
# -----------------------------------------------------------------------
SA_TB    = $(TB_DIR)/tb_bitsys_systolic_array.sv
SA_OUT   = sim_sa

$(SA_OUT): $(RTL_SRCS) $(SA_TB)
	$(IV) $(IFLAGS) -o $@ \
	    $(RTL_SRCS) $(SA_TB)

run_sa: $(SA_OUT)
	./$(SA_OUT)

waves_sa: sim_sa_waves.vcd
	gtkwave $< &

sim_sa_waves.vcd: $(SA_OUT)
	./$(SA_OUT) +dumpvars

# -----------------------------------------------------------------------
all: run_mul run_sa

clean:
	rm -f $(MUL_OUT) $(SA_OUT) *.vcd *.vvp

.PHONY: all sim_mul sim_sa waves_mul waves_sa clean
