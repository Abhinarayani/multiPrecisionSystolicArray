# BitSys Multi-Precision Systolic Array - DE1-SoC Integration

Complete FPGA + Host implementation of the BitSys systolic array accelerator for the Terasic DE1-SoC with Cyclone V.

## Project Structure

```
multiPrecisionSystolicArray/
├── rtl/                          # RTL source files
│   ├── bitsys_*.sv              # Core systolic array modules
│   ├── uart_rx.sv               # UART receiver
│   ├── uart_tx.sv               # UART transmitter
│   └── bitsys_uart_top.sv       # Top-level wrapper (FPGA entry point)
├── quartus/
│   └── setup_project.tcl        # Automated Quartus project setup script
├── host/
│   └── bitsys_host.py           # Python host communication script
├── tb/                          # Simulation testbenches
│   └── tb_bitsys_systolic_array.sv
└── README.md
```

## Hardware Requirements

- **Terasic DE1-SoC Board** with Cyclone V FPGA (5CSEMA5F31C6)
- **USB Cable** (Type-A to Type-B) for JTAG programming
- **USB-to-UART Bridge** (FT232 or similar) for serial communication
- **Jumper Wires** for GPIO connections (optional: use USB-Blaster for UART if available)

## UART Hardware Connection

### Option 1: USB-to-UART Bridge (Recommended)
```
PC USB → USB-to-UART (FT232) → DE1-SoC GPIO Pins
                GND → GND (Pin K5)
                RX  → GPIO_0[0] (Pin D3)
                TX  → GPIO_0[1] (Pin C3)
```

### Pin Mapping for DE1-SoC

| Function     | DE1-SoC Pin | GPIO Header | Notes                |
|--------------|-------------|-------------|----------------------|
| UART RX      | D3          | GPIO_0[0]   | Input from USB bridge|
| UART TX      | C3          | GPIO_0[1]   | Output to USB bridge |
| Precision[0] | A3          | GPIO_0[2]   | Mode select bit 0    |
| Precision[1] | B3          | GPIO_0[3]   | Mode select bit 1    |
| is_signed    | J3          | GPIO_0[4]   | Signed multiply flag |
| bnn_mode     | G3          | GPIO_0[5]   | BNN mode enable      |
| GND          | K5          | GND         | Ground reference     |
| Clock 50 MHz | AF14        | CLOCK_50    | Main system clock    |
| Reset        | AE9         | KEY0        | Active low reset     |

## Step 1: Create Quartus Project

### Option A: Automated (Recommended)

```bash
cd quartus
quartus_sh -t setup_project.tcl
```

This creates `bitsys_de1.qpf` with all settings and pin assignments configured.

### Option B: Manual Setup in Quartus GUI

1. **File → New Project Wizard**
   - Project name: `bitsys_de1`
   - Device: Cyclone V (5CSEMA5F31C6)
   - Files: Add all RTL files from `../rtl/`

2. **Assignments → Device**
   - Family: Cyclone V
   - Device: 5CSEMA5F31C6 (FBGA 896)

3. **Assignments → Pin Planner**
   - Import pin assignments from table above
   - Or use the TCL script automatically

4. **Project Settings**
   - Top-level entity: `bitsys_uart_top`

## Step 2: Compile Design

```bash
# In Quartus project directory (quartus/)

# Method 1: Quartus GUI
Open bitsys_de1.qpf, then click "Start Compilation"

# Method 2: Command line
quartus_map bitsys_de1
quartus_fit bitsys_de1
quartus_asm bitsys_de1
quartus_sta bitsys_de1  # Timing analysis (optional)
```

Output: `bitsys_de1.sof` (SRAM object file for programming)

## Step 3: Program FPGA

### Using Quartus Programmer GUI
1. **Tools → Programmer**
2. **Hardware Setup**: Select USB-Blaster (JTAG)
3. **File**: Select `bitsys_de1.sof`
4. Click **Start** to program

### Using Command Line
```bash
# List available programmers
quartus_pgm -l

# Program FPGA
quartus_pgm -c "USB-Blaster [USB-0]" -m JTAG -o "P;bitsys_de1.sof"
```

## Step 4: Run Host Communication

### Prerequisites
```bash
# Install Python serial library
pip install pyserial
```

### Find Serial Port

**Windows:**
```bash
# List available COM ports
mode
# Or use Device Manager to find COM port
```

**Linux/Mac:**
```bash
ls /dev/ttyUSB*   # Linux
ls /dev/tty.*     # Mac
```

### Run Tests

```bash
cd host

# Test 1: Identity matrix × B
python bitsys_host.py COM3 1

# Test 2: Positive integer matrices
python bitsys_host.py COM3 2

# Test 3: Mixed sign matrices
python bitsys_host.py COM3 3

# Or with custom matrix data
python bitsys_host.py <PORT> <TEST_NUMBER>
```

## Protocol Specification

### UART Parameters
- **Baud Rate**: 115200
- **Data Bits**: 8
- **Stop Bits**: 1
- **Parity**: None
- **Flow Control**: None

### Command Format

| Byte | Value | Description |
|------|-------|-------------|
| 0    | 0x02  | Send A matrix (followed by 16 bytes) |
| 0    | 0x03  | Send B matrix (followed by 16 bytes) |
| 0    | 0x01  | Start computation |
| 0    | 0x04  | Request results (followed by 64 bytes) |

### Data Format

**Matrix Data** (16 bytes per 4×4 matrix)
```
Row-major order: A[0,0], A[0,1], A[0,2], A[0,3], A[1,0], ...
Each element is 8-bit signed integer (-128 to +127)
```

**Result Data** (4 bytes per element, 64 bytes total)
```
Big-endian 32-bit signed integers
Result[0,0]: bytes [31:24], [23:16], [15:8], [7:0]
```

## Precision Modes

Configure via `prec` and related control signals:

| prec[1:0] | Channels | Width | Description |
|-----------|----------|-------|------------|
| 2'b00     | 8        | 1-bit | BNN (only with bnn_mode=1) |
| 2'b01     | 4        | 2-bit | 2-bit quantized |
| 2'b10     | 2        | 4-bit | 4-bit quantized |
| 2'b11     | 1        | 8-bit | Full precision |

## Clock Gating for Power Efficiency

The design implements **integrated clock gating (ICG)** on:
- Skew input registers (gated by `start | data_valid`)
- Clear shift register (gated by `start | data_valid`)
- Cycle counter (gated by `start | cycle_cnt ≠ 0`)
- Output capture (gated by `start | cycle_cnt == DONE_CYCLE`)
- MAC accumulators (gated by `clear | en`)
- MAC data path (gated by `en`)

**Expected Power Savings**:
- Idle: 20-30% reduction
- Active computation: 10-20% reduction

## Timing

For a 4×4 systolic array (N=4):

| Phase | Cycles | Description |
|-------|--------|-------------|
| Input feeding | N | Load A and B into input pipelines |
| Computation | N | PE computation with systolic shifts |
| Drain | N | Final results accumulate at output |
| Total | 3N-1 = 11 | Complete matrix multiply |

At 50 MHz: ~220 ns total latency

## Troubleshooting

### FPGA Programming Fails
- Check USB-Blaster connection
- Verify device is in JTAG mode
- Try: **Tools → Programmer → Auto Detect**

### No Serial Communication
- Verify COM port number
- Check USB-to-UART driver installed
- Confirm RX/TX pins connected correctly
- Test with serial terminal at 115200 baud

### Wrong Results
- Verify precision mode matches systolic array precision setting
- Check matrix data is 8-bit signed (-128 to +127)
- Ensure reset_n pin is pulled high
- Monitor DE1-SoC LEDs for error indicators

### Timing Failures
- Check clock frequency (should be 50 MHz)
- May need to relax constraints or optimize placement
- See timing report: `bitsys_de1.sta`

## Performance Metrics

For 4×4 matrix multiply:
- **Latency**: 11 clock cycles @ 50 MHz = 220 ns
- **Throughput**: ~4.5 million matrix multiplies/sec
- **Power**: ~0.5-1W (estimated, depends on precision mode)
- **Area**: ~3000 LUTs (clock gating optimized)

## Files Reference

| File | Purpose |
|------|---------|
| `uart_rx.sv` | UART receiver (8N1 protocol) |
| `uart_tx.sv` | UART transmitter (8N1 protocol) |
| `bitsys_uart_top.sv` | Top-level FPGA module with protocol handler |
| `setup_project.tcl` | Quartus project creation script |
| `bitsys_host.py` | Python host communication library |

## References

- [Terasic DE1-SoC Documentation](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=167&No=836)
- [Cyclone V Device Datasheet](https://www.intel.com/content/dam/altera-www/global/en_US/pdfs/literature/hb/cv-51002.pdf)
- [Quartus Prime User Guide](https://www.intel.com/content/dam/altera-www/global/en_US/pdfs/literature/ug/ug-qps-13.1.pdf)

## License

This implementation is provided as-is for educational purposes.

## Support

For issues or questions:
1. Check the Troubleshooting section
2. Review timing reports in `bitsys_de1.sta`
3. Run simulation testbench: `vsim -do tb/tb_bitsys_systolic_array.sv`
