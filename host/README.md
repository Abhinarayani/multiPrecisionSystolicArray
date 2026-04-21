# BitSys Host Software

Python utilities for communicating with BitSys systolic array FPGA design on DE1-SoC.

## Quick Start

### Prerequisites
```bash
pip install pyserial
```

### Run Matrix Multiplication Test
```bash
python bitsys_host.py COM3 1
```
*(Replace COM3 with your actual serial port)*

## Scripts

### `bitsys_host.py` - Main Host Controller
Complete communication library for BitSys FPGA design.

**Usage:**
```bash
python bitsys_host.py <PORT> [TEST_NUMBER]
```

**Parameters:**
- `PORT`: Serial port (e.g., COM3, /dev/ttyUSB0)
- `TEST_NUMBER`: 1=Identity, 2=Positive integers, 3=Mixed sign (default=1)

**Example:**
```bash
# Test with DE1-SoC on COM3
python bitsys_host.py COM3 1

# Test with different precision mode
python bitsys_host.py /dev/ttyUSB0 2
```

**Test Cases:**

1. **Test 1: Identity × B**
   - Validates basic functionality
   - Expected: Result = B matrix
   
2. **Test 2: Positive Integer Matrices**
   - Tests arithmetic with 8-bit unsigned values
   - Verifies carry/accumulation

3. **Test 3: Mixed Sign Matrices**
   - Tests 2's complement signed arithmetic
   - Verifies overflow handling

**API Usage:**
```python
from bitsys_host import BitSysHost

# Connect to FPGA
host = BitSysHost("COM3")

# Define matrices
a = [[1, 2, 3, 4],
     [5, 6, 7, 8],
     [9, 10, 11, 12],
     [13, 14, 15, 16]]

b = [[1, 0, 0, 0],
     [0, 1, 0, 0],
     [0, 0, 1, 0],
     [0, 0, 0, 1]]

# Compute C = A × B
result = host.compute(a, b)

# Display result
BitSysHost.print_matrix(result, "Result")

host.close()
```

---

### `uart_monitor.py` - Serial Debugging Tool
Low-level UART monitor for protocol debugging and testing.

**Usage:**
```bash
python uart_monitor.py <PORT> [BAUDRATE]
```

**Modes:**

1. **Monitor Mode** - Listen to all traffic
   - Displays timestamp, data in hex, and ASCII interpretation
   - Useful for observing FPGA → Host responses

2. **Interactive Mode** - Send and receive bytes
   - Type hex bytes: `01 02 03 04`
   - Sends to FPGA and displays response
   - Useful for command testing

**Example:**
```bash
# Monitor all UART traffic
python uart_monitor.py COM3

# Monitor at custom baud rate
python uart_monitor.py /dev/ttyUSB0 57600

# Then select mode when prompted
```

**Sample Interactive Session:**
```
Connected to COM3 @ 115200 baud
Press Ctrl+C to exit

Options:
  1 - Monitor (receive only)
  2 - Interactive (send & receive)
Select mode (1-2): 2

Enter hex bytes to send (e.g., '01 02 03') or 'q' to quit: 01
TX: 01
RX: 01  # FPGA acknowledges

Enter hex bytes to send (e.g., '01 02 03') or 'q' to quit: 02 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F 10
TX: 02010203040506070809...
RX: 02  # FPGA acknowledges matrix receive

Enter hex bytes to send (e.g., '01 02 03') or 'q' to quit: q
```

---

## Protocol Reference

### Command Codes
```
0x01 = Start computation
0x02 = Send A matrix (followed by 16 bytes)
0x03 = Send B matrix (followed by 16 bytes)
0x04 = Request results (FPGA responds with 64 bytes)
```

### Data Format
- **Matrices**: 16 bytes (4×4 in row-major order)
  - Each element: 8-bit signed integer (-128 to +127)
  - Order: A[0,0], A[0,1], A[0,2], A[0,3], A[1,0], ...

- **Results**: 64 bytes (4×4 matrix of 32-bit signed integers)
  - Each element: 4 bytes (big-endian)
  - Example: 0x12345678 → bytes: 0x12, 0x34, 0x56, 0x78

### Communication Sequence
```
Host                          FPGA
  │
  ├─ 0x02 (CMD_SEND_A)  ─────→
  ├─ [16 bytes A] ───────────→
  │
  ├─ 0x03 (CMD_SEND_B)  ─────→
  ├─ [16 bytes B] ───────────→
  │
  ├─ 0x01 (CMD_START)  ──────→  [Computing...]
  │ [wait 500ms]
  │
  ├─ 0x04 (CMD_GET_RESULT) ──→
  │ ←─ [64 bytes result] ──── (C matrix)
  │
```

---

## Troubleshooting

### Serial Connection Issues

**Error: "Port not found" or "Permission denied"**
- Windows: Check Device Manager for COM port
- Linux: Run `ls /dev/ttyUSB*` or `ls /dev/ttyACM*`
- Mac: Run `ls /dev/tty.*`
- Ensure USB-to-UART bridge is connected and drivers installed

**Error: "Could not open port"**
- Port may be in use by another application
- Close Arduino IDE, other terminal programs
- Try unplugging and re-plugging USB

### Data Corruption

**Results don't match expected**
- Check baud rate matches FPGA (115200)
- Verify USB cable quality (try different cable)
- Move USB cable away from power supplies/noise
- Reduce cable length

**Occasional errors but mostly works**
- May indicate marginal clock rate
- Try lowering precision mode test value
- Check power supply to DE1-SoC

### No Response from FPGA

**UART says busy but nothing received**
1. Verify FPGA is programmed (check LED0 on DE1-SoC)
2. Check RX/TX connections:
   - Host RX should connect to FPGA TX (Pin C3)
   - Host TX should connect to FPGA RX (Pin D3)
3. Verify UART pins are configured in Quartus constraints
4. Check reset_n is high (should be pulled up by default)

**Use uart_monitor.py to debug**
```bash
python uart_monitor.py COM3
# Select mode 2 (Interactive)
# Try sending: 01 (START command)
# If FPGA responds, connection is working
```

---

## Performance Notes

### UART Overhead
- Baud rate: 115200 bps (14.4 kB/s)
- Send A matrix: 16 bytes → ~1.4 ms
- Send B matrix: 16 bytes → ~1.4 ms  
- Receive result: 64 bytes → ~5.6 ms
- **Total per multiply**: ~8-9 ms (dominated by serial transfer)

### FPGA Computation Time
- Actual matrix multiply: 220 ns (11 clock cycles @ 50 MHz)
- Negligible compared to serial transfer time
- Throughput bottleneck is serial communication, not computation

### Optimization Tips
- For batch operations, consider using 57600 baud (1.4× slower transfer)
- Can pipeline multiple matrices through UART for streaming mode
- For maximum throughput, implement USB bridge with higher baud rate

---

## Requirements

- Python 3.6+
- `pyserial` package (install with `pip install pyserial`)
- DE1-SoC FPGA programmed with `bitsys_de1.sof`
- USB-to-UART bridge connected (FT232, CP2102, etc.)

## Installation

```bash
# Install pyserial
pip install pyserial

# Optional: Install for user only (no admin required)
pip install --user pyserial
```

## License

Educational use. Part of ECE 751 project.

## Support

For issues:
1. Check device connections with `uart_monitor.py`
2. Verify FPGA programming with Quartus Programmer
3. Review QUARTUS_DE1_GUIDE.md for hardware setup
4. Check timing reports for potential signal integrity issues
