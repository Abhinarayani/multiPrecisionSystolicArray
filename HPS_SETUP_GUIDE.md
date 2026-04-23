# HPS UART to FPGA Fabric Routing Setup

Complete guide for routing HPS UART peripheral to FPGA pins (B25/C25) on DE1-SoC.

## Overview

Instead of using GPIO pins directly, this approach:
- Uses the HPS UART peripheral
- Routes signals through FPGA fabric (via Platform Designer)
- Connects to dedicated HPS pins B25 (RX) and C25 (TX)
- Reduces pin conflicts and uses integrated HPS resources

## Step-by-Step Setup

### Step 1: Create Platform Designer System (Qsys)

1. **Open Quartus Prime**
   - File → New Project Wizard
   - Project name: `bitsys_de1`
   - Device: 5CSEMA5F31C6
   - Top-level entity: `bitsys_uart_top`

2. **Create HPS System**
   - Tools → Platform Designer (Qsys)
   - File → New
   - Save as: `hps_system.qsys`

3. **Add HPS Component**
   - IP Catalog (bottom left)
   - Search: "Cyclone V HPS"
   - Double-click: "Cyclone V HPS"
   - This adds the HPS instance to your system

4. **Configure HPS UART Multiplexing**
   
   In the HPS component parameters panel:
   - Expand: "HPS" section
   - Expand: "Peripheral Pin Mux" (or "UART0")
   - Find the UART0 peripheral
   - Change from: "HPS I/O Set X" → **"FPGA"**
   - This routes UART0 (RX/TX) to the FPGA fabric instead of HPS pins
   
   **Key Settings to Enable:**
   - UART0: Enable (check)
   - Route to: FPGA (select)

5. **Add System Components**
   
   a. Clock Source:
   - IP Catalog → "Clock Source"
   - Double-click to add
   - Frequency: 50 MHz
   - Export as "clk_50"
   
   b. Reset Controller:
   - IP Catalog → "Reset Controller"
   - Double-click to add
   - Output assertion: "Active Low"
   - Connect clock to reset controller
   - Export as "reset_n"

6. **Make Connections in Qsys**
   
   Connect the clock and reset to HPS:
   - clk_source.clk → hps.clk_reset_clk
   - reset_controller.reset_out → hps.clk_reset_reset

7. **Export UART Signals**
   
   Right-click on HPS component → "Export":
   - hps_io → "hps_io" (HPS I/O port, needed for configuration pins)
   - uart0_rx → "uart_rx"
   - uart0_tx → "uart_tx"
   - uart0_cts → "uart_cts" (optional, for flow control)
   - uart0_rts → "uart_rts" (optional, for flow control)

8. **Save and Generate**
   - File → Save
   - Click "Generate HDL" button
   - Select: SystemVerilog
   - Location: same directory as .qsys file
   - Click "Generate"
   
   This creates:
   - `hps_system.qsys` (Qsys project)
   - `hps_system.sv` (generated HDL wrapper)
   - `hps_system` folder (HDL includes)

### Step 2: Create Top-Level Wrapper

The generated `hps_system.sv` wraps the HPS. Now create a new top-level entity that:
1. Instantiates the HPS system
2. Connects your BitSys systolic array
3. Interfaces UART with your logic

**File: `rtl/bitsys_hps_top.sv`** (provided separately)

### Step 3: Update Quartus Project

1. **Add Files to Project**
   - Add `hps_system.sv` (generated from Qsys)
   - Add `bitsys_hps_top.sv` (your new wrapper)
   - Keep all existing RTL files
   - Set TOP_LEVEL_ENTITY: `bitsys_hps_top` (not `bitsys_uart_top`)

2. **Update Pin Assignments**
   
   In Quartus Assignments → Pin Planner:
   
   ```
   Signal             | Pin  | I/O Standard    | Comment
   ─────────────────────────────────────────────────────────
   clk                | AF14 | 3.3-V LVTTL     | CLOCK_50
   reset_n            | AE9  | 3.3-V LVTTL     | KEY0
   hps_io[*]          | auto | Auto (HPS)      | HPS I/O (auto-assigned)
   uart_rx (from FPGA)| B25  | 3.3-V LVTTL     | HPS UART RX
   uart_tx (to FPGA)  | C25  | 3.3-V LVTTL     | HPS UART TX
   ```
   
   **Key Point**: B25 and C25 are now HPS pins, not GPIO. They are automatically configured when you assign them to `uart_rx` and `uart_tx` signals.

### Step 4: Compile and Program

```bash
# Command-line compilation
cd quartus
quartus_map bitsys_de1
quartus_fit bitsys_de1
quartus_asm bitsys_de1
quartus_sta bitsys_de1

# Or use GUI: Project → Start Compilation
```

Output: `bitsys_de1.sof`

### Step 5: Program and Test

```bash
# Program FPGA
quartus_pgm -c "USB-Blaster [USB-0]" -m JTAG -o "P;bitsys_de1.sof"

# Run Python host test
cd ..
python bitsys_uart_test.py --port COM3
```

---

## Qsys System Diagram

```
┌─────────────────────────────────────────────┐
│           Platform Designer System           │
│                                             │
│  ┌──────────┐      ┌──────────────────────┐ │
│  │clk_source│─────→│ Cyclone V HPS        │ │
│  │(50 MHz)  │      │                      │ │
│  └──────────┘      │ UART0 (routed to     │ │
│                    │  FPGA fabric)        │ │
│  ┌──────────┐      │                      │ │
│  │rst_ctrl  │─────→│ hps_io[*] ←─────────│ │
│  │(active-L)│      │ uart_rx   ←───────┐ │ │
│  └──────────┘      │ uart_tx   ────────→ │ │
│                    └──────────────────────┘ │
│                           ↓                  │
│                    FPGA Pins B25, C25       │
└─────────────────────────────────────────────┘
        ↓
   DE1-SoC Board
```

---

## Important Notes

1. **HPS I/O Pins**: The `hps_io[*]` signal is critical. It includes ALL HPS pin configurations. Quartus auto-assigns these, so don't manually reassign them.

2. **Timing**: The HPS uses the same 50 MHz clock as the FPGA fabric. No clock domain crossing needed.

3. **UART Flow Control**: CTS/RTS are optional. If not needed, tie them to default values or leave unconnected.

4. **Reset**: Active-low reset (from KEY0) resets both HPS and FPGA logic.

5. **Device Configuration**: The HPS handles its own I/O configuration. You just need to provide clock, reset, and connect the uart_rx/tx signals.

---

## Troubleshooting

**Error: "HPS I/O pins have unassigned locations"**
- Ensure `hps_io[*]` is NOT manually assigned in Quartus
- Let Quartus auto-assign HPS pins
- These are pre-determined on the DE1-SoC

**Error: "uart_rx/tx cannot be placed at B25/C25"**
- Verify Qsys exported the UART signals correctly
- Check that UART0 is set to "FPGA" route in HPS parameters
- Regenerate Qsys system

**UART not communicating:**
- Verify clock: 50 MHz clock must reach HPS
- Verify reset: Active-low reset must pulse on startup
- Check baud rate in Python script matches baud rate expected (115200)
- Verify USB-to-UART adapter is properly wired to B25 (RX) and C25 (TX)

---

## References

- **Altera Cyclone V FPGA Configuration User Guide**: HPS I/O Multiplexing
- **DE1-SoC User Manual**: Schematic and pin assignments
- **Terasic Example Projects**: Pre-built HPS + FPGA examples
