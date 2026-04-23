# Platform Designer (Qsys) Quick Reference - HPS UART Configuration

## Visual Step-by-Step Guide for Routing HPS UART to FPGA Fabric

### Step 1: Add HPS Component
```
IP Catalog (lower left panel)
  ↓
Search: "Cyclone V HPS" 
  ↓
Double-click "Cyclone V HPS v21.0" (or latest version)
```

Result: HPS component appears in the main canvas

### Step 2: Configure HPS Parameters Panel

After adding HPS, the **HPS** panel appears on the right side.

**CRITICAL SETTINGS:**

```
┌─ HPS (main section) ──────────────────────────────────┐
│                                                        │
├─ Clocks ─────────────────────────────────────────────┤
│  ✓ h2f_reset Enable                                  │
│  ✓ f2h_reset Enable                                  │
│                                                        │
├─ Peripherals ────────────────────────────────────────┤
│  ┌─ UART0 ──────────────────────────────────────┐   │
│  │ ✓ Enable UART0                               │   │
│  │                                               │   │
│  │ Selected Pin → [FPGA] ← CLICK THIS           │   │
│  │              (NOT "HPS I/O Set 1")           │   │
│  │                                               │   │
│  │ Flow Control: □ (Optional, leave unchecked)  │   │
│  └───────────────────────────────────────────────┘   │
│                                                        │
│  ┌─ HPS I/O ────────────────────────────────────┐   │
│  │ This shows which pins are used by HPS        │   │
│  │ You'll see UART_RX, UART_TX entries after    │   │
│  │ switching to FPGA mode above                 │   │
│  └───────────────────────────────────────────────┘   │
│                                                        │
└────────────────────────────────────────────────────────┘
```

**Key Action: Change UART0 "Selected Pin" from "HPS I/O Set X" to "FPGA"**

This makes UART signals appear as exported pins instead of fixed HPS pins.

### Step 3: Add Clock Source

```
IP Catalog
  ↓
Search: "Clock Source"
  ↓
Double-click "Clock Source"
```

**Configure Clock Source:**
- Frequency: 50000000 (50 MHz)
- Name: clk_0 (or "clk_source")

### Step 4: Add Reset Controller

```
IP Catalog
  ↓
Search: "Reset Controller"  
  ↓
Double-click "Reset Controller"
```

**Configure Reset Controller:**
- Output Assertion: "Active Low"
- Name: reset_0

### Step 5: Make Connections

In the main Qsys canvas, connect the signals:

**Connection 1:** Clock → HPS
```
clk_0.clk_out ──→ hps.clk_reset_clk
```

**Connection 2:** Reset → HPS  
```
reset_0.reset_out ──→ hps.clk_reset_reset
```

**To make connections:** Click output dot of one signal, drag to input of target

### Step 6: Export Signals

Right-click on each signal and select **Export**:

```
hps
├─ hps_io              → Export as "hps_io"
├─ uart0_rx (FPGA mode) → Export as "uart_rx"
├─ uart0_tx (FPGA mode) → Export as "uart_tx"
├─ uart0_cts (optional) → Export as "uart_cts"
└─ uart0_rts (optional) → Export as "uart_rts"

clk_0
└─ clk_out            → (No export needed, internal only)

reset_0
└─ reset_out          → (No export needed, internal only)
```

Exported signals appear with this icon: **[→→]**

### Step 7: Generate System

Menu bar:
```
File → Save (saves as hps_system.qsys)
  ↓
"Generate HDL" button (bottom right, or Generate → Generate HDL)
  ↓
Select:
  ☑ Create HDL design files
  ☑ Create IP catalog files
  ☐ Create simulation files (optional)
  ○ SystemVerilog (selected)
  ○ Verilog HDL
  
Click: Generate
```

**Output Files Created:**
```
quartus/
├── hps_system.qsys         (your system definition)
├── hps_system.sv           (generated HDL wrapper) ← IMPORTANT
├── hps_system.qip          (IP catalog definition)
└── hps_system/             (folder with generated sources)
    ├── synthesis/
    └── ...
```

### Step 8: Back in Quartus

1. Add generated files to project:
   ```
   Project → Add Files...
   Select: hps_system.sv
   Select: hps_system.qip
   ```

2. Set top-level entity:
   ```
   Assignments → Settings → Top-level entity
   Set to: bitsys_hps_top
   ```

3. Assign pins in Pin Planner:
   ```
   Assignments → Pin Planner
   
   Signal Name     | Location | I/O Standard
   ─────────────────────────────────────────
   clk             | AF14     | 3.3-V LVTTL
   rst_n           | AE9      | 3.3-V LVTTL
   uart_rx         | B25      | 3.3-V LVTTL
   uart_tx         | C25      | 3.3-V LVTTL
   hps_io[*]       | auto     | (DO NOT ASSIGN)
   ```

4. Compile:
   ```
   Project → Start Compilation
   (or quartus_map, quartus_fit, quartus_asm from command line)
   ```

---

## Common Mistakes to Avoid

| ❌ Mistake | ✓ Correct |
|-----------|-----------|
| Leave UART in "HPS I/O Set" mode | **Change to "FPGA" mode** in Qsys |
| Manually assign `hps_io[*]` pins | **Leave hps_io[*] unassigned** - Quartus auto-assigns |
| Use GPIO pins D3/C3 instead of B25/C25 | **Use B25/C25** - these are the HPS UART pins |
| Forget to export uart_rx/tx signals | **Always export** these from HPS component |
| Use Verilog instead of SystemVerilog | **Use SystemVerilog** generation in Qsys |
| Don't connect clock/reset to HPS | **Clock and reset MUST be connected** for HPS to function |

---

## Verification Checklist

- [ ] Qsys system created with HPS (hps_system.qsys exists)
- [ ] UART0 configured to route to "FPGA"
- [ ] Clock source added and connected to HPS
- [ ] Reset controller added and connected to HPS
- [ ] uart_rx, uart_tx, hps_io exported from HPS
- [ ] hps_system.sv generated successfully
- [ ] bitsys_hps_top.sv instantiates both HPS and BitSys
- [ ] Quartus project includes hps_system.sv and hps_system.qip
- [ ] Top-level entity set to bitsys_hps_top
- [ ] Pin assignments: clk→AF14, rst_n→AE9, uart_rx→B25, uart_tx→C25
- [ ] Project compiles without errors

---

## If Compilation Fails

**Error: "SOPC Builder was unsuccessful"**
- Qsys generation failed. Re-generate hps_system.sv.

**Error: "hps_system.sv not found"**
- Ensure hps_system.sv exists in quartus/ directory after Qsys generation.

**Error: "HPS I/O pins unassigned"**
- Quartus cannot auto-assign HPS pins. This is normal for HPS components.
- Do NOT manually assign hps_io[*] pins. Quartus handles this automatically.

**Error: "uart_rx/tx cannot fit at B25/C25"**
- B25 and C25 must be valid HPS UART pins on your device.
- Verify device is 5CSEMA5F31C6.
- Check schematic: these pins should be marked as "UART RX" and "UART TX" from HPS.
