## Clock with frequency of 20000ps = 50 MHz (typical FPGA clock)
create_clock -name "clk" -period 20000  { clk }
set_dont_touch_network [find port clk]

## Pointer to all inputs except clk
set prim_inputs [remove_from_collection [all_inputs] [find port clk]]
## Pointer to all inputs except clk and rst_n
## set prim_inputs_no_rst [remove_from_collection $prim_inputs [find port rst_n]]
## Set clk uncertainty (skew) - increased to account for synthesis margin
set_clock_uncertainty 0.05 clk
set_clock_transition 32 clk

## Set input delay & drive on all inputs (realistic margin)
set_input_delay -clock clk 0.5 [copy_collection $prim_inputs]
## rst_n goes to many places so don't touch
#set_dont_touch_network [find port rst_n]

## Set output delay & load on all outputs (realistic margin)
set_output_delay -clock clk 0.500 [all_outputs]
set_load 0.010 [all_outputs]

## Wire load model allows it to estimate internal parasitics 
#set_wire_load_model -name TSMC32K_Lowk_Conservative -library tcbn45gsbwptc
set_wire_load_mode "segmented" 

## Max transition time - relaxed for better hold timing
#set_max_transition 0.1 [current_design]

set_max_fanout 128 bitsys_systolic_array

set_host_options -max_cores 8