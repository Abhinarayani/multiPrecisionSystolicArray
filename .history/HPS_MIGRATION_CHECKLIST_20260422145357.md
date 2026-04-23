# HPS UART Migration Summary

Complete checklist for migrating from GPIO-based UART (D3/C3) to HPS-routed UART (B25/C25).

## What Changed

### Before (GPIO Direct)
- UART RX: GPIO_0[0] → PIN D3
- UART TX: GPIO_0[1] → PIN C3
- No HPS involvement
- Module: `bitsys_uart_top.sv` (direct GPIO)

### After (HPS-Routed)
- UART RX: HPS UART0 → routed to FPGA fabric → PIN B25
- UART TX: HPS UART0 → routed to FPGA fabric → PIN C25
- Uses HPS peripheral for UART
- Wrapper: `bitsys_hps_top.sv` (instantiates HPS + BitSys)

---

## Implementation Checklist

### Phase 1: Create HPS System (One-time in Qsys)

- [ ] **Launch Platform Designer**
  ```bash
  quartus → Tools → Platform Designer (Qsys)
  ```

- [ ] **Create new Qsys system**
  ```
  File → New → "hps_system"
  ```

- [ ] **Follow QSYS_CONFIGURATION_GUIDE.md** (detailed steps)
  - Add Cyclone V HPS component
  - Change UART0 to route to FPGA (critical!)
  - Add Clock Source (50 MHz)
  - Add Reset Controller (active low)
  - Connect clock and reset to HPS
  - Export: hps_io, uart_rx, uart_tx

- [ ] **Generate HDL**
  ```
  Generate → Generate HDL
  Select: SystemVerilog
  ```

- [ ] **Verify generated files**
  ```
  quartus/
  ├── hps_system.qsys
  ├── hps_system.sv      ← CRITICAL FILE
  ├── hps_system.qip
  └── hps_system/
  ```

### Phase 2: Update Quartus Project

- [ ] **Created: `rtl/bitsys_hps_top.sv`**
  - Instantiates hps_system
  - Instantiates bitsys_uart_top
  - Connects UART signals from HPS

- [ ] **Update Quartus project (.qpf)**
  ```tcl
  # Add new files to project:
  set_global_assignment -name SYSTEMVERILOG_FILE ../rtl/bitsys_hps_top.sv
  set_global_assignment -name SYSTEMVERILOG_FILE hps_system.sv
  set_global_assignment -name QIP_FILE hps_system.qip
  
  # Change top-level entity:
  set_global_assignment -name TOP_LEVEL_ENTITY bitsys_hps_top
  ```

- [ ] **Update pin assignments in Quartus**
  ```
  Signal          | Old Pin | New Pin | Reason
  ────────────────────────────────────────────────
  clk             | AF14    | AF14    | (unchanged)
  rst_n           | AE9     | AE9     | (unchanged, was AA14)
  uart_rx         | D3      | B25     | HPS UART RX pin
  uart_tx         | C3      | C25     | HPS UART TX pin
  hps_io[*]       | —       | auto    | Auto-assigned by HPS
  ```

### Phase 3: Build and Test

- [ ] **Compile design**
  ```bash
  cd quartus
  quartus_map bitsys_de1
  quartus_fit bitsys_de1
  quartus_asm bitsys_de1
  ```

- [ ] **Program FPGA**
  ```bash
  quartus_pgm -c "USB-Blaster [USB-0]" -m JTAG -o "P;bitsys_de1.sof"
  ```

- [ ] **Wire USB-to-UART adapter**
  ```
  Adapter GND → DE1 GND (any GND pin)
  Adapter RX  → DE1 PIN B25
  Adapter TX  → DE1 PIN C25
  ```

- [ ] **Run tests**
  ```bash
  python bitsys_uart_test.py --port COM3
  ```

---

## File Changes Summary

### New Files Created

| File | Purpose |
|------|---------|
| `rtl/bitsys_hps_top.sv` | Top-level wrapper for HPS + BitSys |
| `HPS_SETUP_GUIDE.md` | Complete HPS setup documentation |
| `QSYS_CONFIGURATION_GUIDE.md` | Step-by-step Qsys visual guide |
| `quartus/setup_project_hps.tcl` | Updated Quartus setup script |

### Modified Files

| File | Changes |
|------|---------|
| `bitsys_de1.qsf` | Update pin assignments (B25/C25 instead of D3/C3) |
| N/A (create new project) | Top-level entity: `bitsys_hps_top` (was `bitsys_uart_top`) |

### Unchanged Files

All RTL logic remains the same:
- `bitsys_uart_top.sv` (still used, now instantiated by bitsys_hps_top)
- `uart_rx.sv`, `uart_tx.sv`
- All BitSys systolic array modules
- Test scripts (bitsys_uart_test.py)

---

## Advantages of HPS Routing

| Aspect | GPIO Direct | HPS-Routed |
|--------|-------------|-----------|
| **Pins Used** | 2 GPIO pins (D3, C3) | 2 HPS pins (B25, C25) |
| **Pin Flexibility** | Limited to GPIO_0 | Any FPGA-accessible pin |
| **UART Hardware** | Software UART logic | HPS UART peripheral |
| **Pin Conflicts** | May conflict with other GPIO | Dedicated HPS resource |
| **Configuration** | Simple, direct | Requires Qsys |
| **HPS Available** | Not used | Used for UART only |
| **Scalability** | Can't easily add I2C/SPI | Easy to add peripherals via Qsys |

---

## Troubleshooting

### Issue: "hps_system.sv not found" after Qsys generation

**Solution:**
1. Verify Qsys ran successfully (check for hps_system.sv in quartus/ folder)
2. Re-run Qsys and explicitly click "Generate HDL"
3. Add hps_system.sv to Quartus project manually via Project → Add Files

### Issue: Compilation error "hps_io constraint conflict"

**Solution:**
- **Do NOT** manually assign hps_io[*] pins in Quartus Pin Planner
- These are auto-assigned by the HPS component
- Remove any manual assignments to hps_io

### Issue: UART still not communicating

**Solution:**
1. Verify correct pins wired: B25 (RX) and C25 (TX)
2. Check baud rate: must be 115200
3. Test with oscilloscope/logic analyzer on B25/C25
4. Verify HPS UART enabled in Qsys
5. Check clock (50 MHz) is reaching HPS

### Issue: Qsys "Selected Pin" dropdown doesn't show "FPGA" option

**Solution:**
- You may have an older HPS IP version
- Update to latest Platform Designer version
- Or manually edit the Qsys XML to enable FPGA routing (advanced)

---

## Reference Documents

- `HPS_SETUP_GUIDE.md` — Complete step-by-step guide
- `QSYS_CONFIGURATION_GUIDE.md` — Visual Qsys walkthrough
- `QUARTUS_DE1_GUIDE.md` — General DE1-SOC compilation guide
- Altera Cyclone V Handbook — HPS datasheet
- Terasic DE1-SoC Schematic — Pin mappings

---

## Next Steps

1. **Generate Qsys system** (follow QSYS_CONFIGURATION_GUIDE.md)
2. **Create Quartus project** using setup_project_hps.tcl
3. **Compile and program** FPGA
4. **Connect USB-to-UART** to B25 (RX) and C25 (TX)
5. **Run tests** with bitsys_uart_test.py

Good luck! 🚀
