#!/usr/bin/env python3
"""
bitsys_uart_test.py
PC-side test script for bitsys_uart_top running on FPGA.

Communicates over a USB-to-UART adapter (e.g. CP2102, FT232, CH340).

─── Packet format ────────────────────────────────────────────────────────────
  PC → FPGA  33 bytes:
    Byte  0   : config = { bnn_mode[7], is_signed[6], prec[5:4], 4'b0 }
    Bytes 1–16: Matrix A, row-major, signed int8
    Bytes 17–32: Matrix B, row-major, signed int8

  FPGA → PC  64 bytes:
    C[0][0]…C[3][3], each element as 4 bytes big-endian signed int32

─── Usage ────────────────────────────────────────────────────────────────────
  python bitsys_uart_test.py                        # auto-detect port
  python bitsys_uart_test.py --port COM3            # Windows
  python bitsys_uart_test.py --port /dev/ttyUSB0   # Linux
  python bitsys_uart_test.py --port /dev/tty.usbserial-0001  # macOS
  python bitsys_uart_test.py --list                 # list available ports
"""

import argparse
import struct
import sys
import time
import serial
import serial.tools.list_ports

# ─── Constants ────────────────────────────────────────────────────────────────
BAUD_RATE   = 115_200
N           = 4          # systolic array dimension
RX_BYTES    = 33         # bytes sent PC → FPGA
TX_BYTES    = 64         # bytes received FPGA → PC
TIMEOUT_S   = 5.0        # seconds to wait for full 64-byte response

# Precision mode encoding (matches bitsys_pkg)
PREC_1B = 0b00
PREC_2B = 0b01
PREC_4B = 0b10
PREC_8B = 0b11


# ─── Helpers ──────────────────────────────────────────────────────────────────

def build_config_byte(prec: int, is_signed: bool, bnn_mode: bool) -> int:
    """Pack control bits into config byte: {bnn_mode[7], is_signed[6], prec[5:4], 4'b0}"""
    return ((1 if bnn_mode  else 0) << 7) | \
           ((1 if is_signed else 0) << 6) | \
           ((prec & 0x3)            << 4)


def build_packet(A, B, prec=PREC_8B, is_signed=True, bnn_mode=False) -> bytes:
    """
    Flatten config + A + B into a 33-byte packet.

    A, B : 4×4 lists of ints (signed, –128..127 for 8-bit mode)
    """
    cfg = build_config_byte(prec, is_signed, bnn_mode)
    payload = bytearray([cfg])
    for row in A:
        for val in row:
            payload.append(val & 0xFF)   # signed → unsigned byte
    for row in B:
        for val in row:
            payload.append(val & 0xFF)
    assert len(payload) == RX_BYTES, f"Packet length {len(payload)} != {RX_BYTES}"
    return bytes(payload)


def parse_result(raw: bytes):
    """
    Decode 64-byte response into a 4×4 list of signed int32 values.
    Each element is 4 bytes big-endian.
    """
    assert len(raw) == TX_BYTES, f"Response length {len(raw)} != {TX_BYTES}"
    C = []
    for i in range(N):
        row = []
        for j in range(N):
            idx = (i * N + j) * 4
            val = struct.unpack('>i', raw[idx:idx+4])[0]   # big-endian signed int32
            row.append(val)
        C.append(row)
    return C


def ref_matmul(A, B):
    """Pure-Python reference: C = A × B (signed 32-bit accumulation)."""
    C = [[0]*N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            s = 0
            for k in range(N):
                s += int(A[i][k]) * int(B[k][j])
            C[i][j] = s
    return C


def matrix_str(M, width=8):
    """Pretty-print a matrix."""
    lines = []
    for row in M:
        lines.append("  " + " ".join(f"{v:{width}d}" for v in row))
    return "\n".join(lines)


# ─── UART helpers ─────────────────────────────────────────────────────────────

def list_ports():
    """Print all available serial ports."""
    ports = serial.tools.list_ports.comports()
    if not ports:
        print("No serial ports found.")
        return
    print("Available serial ports:")
    for p in sorted(ports):
        print(f"  {p.device:20s}  {p.description}")


def auto_detect_port() -> str:
    """
    Return the first port that looks like a USB-UART adapter.
    Checks for common chip descriptions: CP210x, FT232, CH340, PL2303.
    Falls back to the first available port if none match.
    Raises RuntimeError if no ports are found at all.
    """
    ports = serial.tools.list_ports.comports()
    if not ports:
        raise RuntimeError("No serial ports found. Is the USB-UART adapter plugged in?")

    keywords = ["cp210", "ft232", "ch340", "ch341", "pl2303", "usb serial", "uart"]
    for p in sorted(ports):
        desc = p.description.lower()
        if any(k in desc for k in keywords):
            print(f"Auto-detected USB-UART adapter: {p.device}  ({p.description})")
            return p.device

    # Fallback: first port
    p = sorted(ports)[0]
    print(f"No recognised USB-UART adapter found; using first port: {p.device}  ({p.description})")
    return p.device


def open_port(port: str) -> serial.Serial:
    """Open and configure the serial port."""
    ser = serial.Serial(
        port=port,
        baudrate=BAUD_RATE,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=TIMEOUT_S,
    )
    # Flush any stale data from a previous run
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    time.sleep(0.05)   # let the FPGA settle after DTR/RTS toggling
    return ser


# ─── Core test runner ─────────────────────────────────────────────────────────

def run_test(ser: serial.Serial,
             test_name: str,
             A, B,
             prec=PREC_8B,
             is_signed=True,
             bnn_mode=False,
             verbose=True) -> bool:
    """
    Send one matrix-multiply request and verify the response.

    Returns True on PASS, False on FAIL.
    """
    C_ref = ref_matmul(A, B)
    packet = build_packet(A, B, prec=prec, is_signed=is_signed, bnn_mode=bnn_mode)

    if verbose:
        print(f"\n{'─'*54}")
        print(f"  {test_name}")
        print(f"{'─'*54}")
        cfg = packet[0]
        print(f"  Config byte : 0x{cfg:02X}  "
              f"(prec={prec:02b}, is_signed={int(is_signed)}, bnn_mode={int(bnn_mode)})")

    # ── Send ──────────────────────────────────────────────────────────────────
    ser.reset_input_buffer()
    n_sent = ser.write(packet)
    ser.flush()
    if verbose:
        print(f"  Sent        : {n_sent} bytes  →  FPGA")

    # ── Receive ───────────────────────────────────────────────────────────────
    t0 = time.monotonic()
    raw = bytearray()
    while len(raw) < TX_BYTES:
        chunk = ser.read(TX_BYTES - len(raw))
        if not chunk:
            elapsed = time.monotonic() - t0
            print(f"\n  TIMEOUT after {elapsed:.2f}s  "
                  f"(received {len(raw)}/{TX_BYTES} bytes)")
            return False
        raw.extend(chunk)

    elapsed = time.monotonic() - t0
    if verbose:
        print(f"  Received    : {len(raw)} bytes  ←  FPGA  ({elapsed*1000:.1f} ms)")

    # ── Parse & compare ───────────────────────────────────────────────────────
    C_dut = parse_result(bytes(raw))

    errors = 0
    for i in range(N):
        for j in range(N):
            if C_dut[i][j] != C_ref[i][j]:
                errors += 1

    if verbose:
        print(f"\n  Expected C:")
        print(matrix_str(C_ref))
        print(f"\n  DUT C (via UART):")
        print(matrix_str(C_dut))

    if errors == 0:
        print(f"\n  ✓  PASS — all {N*N} elements correct")
        return True
    else:
        print(f"\n  ✗  FAIL — {errors} mismatches")
        for i in range(N):
            for j in range(N):
                if C_dut[i][j] != C_ref[i][j]:
                    print(f"     C[{i}][{j}]  expected={C_ref[i][j]}  got={C_dut[i][j]}")
        return False


# ─── Test suite ───────────────────────────────────────────────────────────────

def run_all_tests(ser: serial.Serial) -> int:
    """Run all test cases. Returns number of failures."""

    # ── Test 1: Identity × B1 ─────────────────────────────────────────────────
    A_I = [[0]*N for _ in range(N)]
    for k in range(N):
        A_I[k][k] = 1

    B1 = [
        [ 1,  2,  3,  4],
        [ 5,  6,  7,  8],
        [ 9, 10, 11, 12],
        [13, 14, 15, 16],
    ]

    # ── Test 2: Positive integers ─────────────────────────────────────────────
    A2 = [
        [1, 2, 3, 4],
        [5, 6, 7, 8],
        [2, 1, 4, 3],
        [4, 3, 2, 1],
    ]
    B2 = [
        [1, 0, 0, 1],
        [0, 1, 1, 0],
        [2, 2, 0, 0],
        [0, 0, 3, 3],
    ]

    # ── Test 3: Mixed sign ────────────────────────────────────────────────────
    A3 = [
        [  3,  -2,   1,  -4],
        [ -5,   6,  -7,   8],
        [  9, -10,  11, -12],
        [-13,  14, -15,  16],
    ]
    B3 = [
        [  2,  -1,   3,  -2],
        [ -4,   5,  -6,   7],
        [  8,  -9,  10, -11],
        [-12,  13, -14,  15],
    ]

    # ── Test 4: Extreme values (−128 / 127 / identity-like B) ─────────────────
    A4 = [
        [-128, -128, -128, -128],
        [ 127,  127,  127,  127],
        [  -1,    1,   -1,    1],
        [   0,    0,    0,    0],
    ]
    B4 = [
        [1, 0, 0, 0],
        [0, 1, 0, 0],
        [0, 0, 1, 0],
        [0, 0, 0, 1],
    ]

    tests = [
        ("Test 1: Identity × B1",     A_I, B1),
        ("Test 2: Positive integers",  A2,  B2),
        ("Test 3: Mixed sign",         A3,  B3),
        ("Test 4: Extreme values",     A4,  B4),
    ]

    failures = 0
    for name, A, B in tests:
        ok = run_test(ser, name, A, B)
        if not ok:
            failures += 1
        # Small gap between tests so FPGA returns cleanly to S_IDLE
        time.sleep(0.1)

    return failures


# ─── Entry point ──────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="PC-side UART test for bitsys_uart_top on FPGA")
    parser.add_argument("--port", "-p",
                        help="Serial port (e.g. COM3, /dev/ttyUSB0). "
                             "Auto-detected if omitted.")
    parser.add_argument("--baud", "-b", type=int, default=BAUD_RATE,
                        help=f"Baud rate (default {BAUD_RATE})")
    parser.add_argument("--list", "-l", action="store_true",
                        help="List available serial ports and exit")
    parser.add_argument("--timeout", "-t", type=float, default=TIMEOUT_S,
                        help=f"Per-test receive timeout in seconds (default {TIMEOUT_S})")
    args = parser.parse_args()

    if args.list:
        list_ports()
        return

    port = args.port or auto_detect_port()

    print(f"\n{'='*54}")
    print(f"  BitSys UART Test  —  port={port}  baud={args.baud}")
    print(f"{'='*54}")

    try:
        ser = open_port(port)
    except serial.SerialException as e:
        print(f"\nERROR: Could not open {port}: {e}")
        print("Run with --list to see available ports.")
        sys.exit(1)

    try:
        failures = run_all_tests(ser)
    finally:
        ser.close()

    print(f"\n{'='*54}")
    if failures == 0:
        print(f"  ALL TESTS PASSED")
    else:
        print(f"  {failures} TEST(S) FAILED")
    print(f"{'='*54}\n")

    sys.exit(0 if failures == 0 else 1)


if __name__ == "__main__":
    main()
