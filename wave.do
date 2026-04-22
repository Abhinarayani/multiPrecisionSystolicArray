onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_uart_design/clk
add wave -noupdate /tb_uart_design/rst_n
add wave -noupdate /tb_uart_design/rx
add wave -noupdate /tb_uart_design/tx
add wave -noupdate /tb_uart_design/prec
add wave -noupdate /tb_uart_design/is_signed
add wave -noupdate /tb_uart_design/bnn_mode
add wave -noupdate /tb_uart_design/test_count
add wave -noupdate /tb_uart_design/pass_count
add wave -noupdate /tb_uart_design/fail_count
add wave -noupdate /tb_uart_design/u_dut/clk
add wave -noupdate /tb_uart_design/u_dut/rst_n
add wave -noupdate /tb_uart_design/u_dut/rx
add wave -noupdate /tb_uart_design/u_dut/tx
add wave -noupdate /tb_uart_design/u_dut/prec
add wave -noupdate /tb_uart_design/u_dut/is_signed
add wave -noupdate /tb_uart_design/u_dut/bnn_mode
add wave -noupdate /tb_uart_design/u_dut/uart_rx_data
add wave -noupdate /tb_uart_design/u_dut/uart_rx_valid
add wave -noupdate /tb_uart_design/u_dut/uart_tx_data
add wave -noupdate /tb_uart_design/u_dut/uart_tx_send
add wave -noupdate /tb_uart_design/u_dut/uart_tx_busy
add wave -noupdate /tb_uart_design/u_dut/sa_start
add wave -noupdate /tb_uart_design/u_dut/sa_output_valid
add wave -noupdate /tb_uart_design/u_dut/sa_cycle
add wave -noupdate /tb_uart_design/u_dut/sa_is_computing
add wave -noupdate /tb_uart_design/u_dut/rx_byte_count
add wave -noupdate /tb_uart_design/u_dut/rx_state
add wave -noupdate /tb_uart_design/u_dut/result_idx
add wave -noupdate /tb_uart_design/u_dut/tx_byte_idx
add wave -noupdate /tb_uart_design/u_dut/sending_results
add wave -noupdate /tb_uart_design/u_dut/cmd_get_results
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 2
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ps} {210 ms}
