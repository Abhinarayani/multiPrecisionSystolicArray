#!/usr/bin/env python3
"""
BitSys Systolic Array UART Host Communication
For Terasic DE1-SoC with Cyclone V

Sends two 4x4 matrices to FPGA, receives computation results.
Usage: python bitsys_host.py <COM_PORT> [precision] [signed] [bnn_mode]
Example: python bitsys_host.py COM3 3 1 0
"""

import serial
import time
import struct
import sys
from typing import List, Tuple


class BitSysHost:
    """Host controller for BitSys systolic array via UART"""

    # UART Commands
    CMD_START = 0x01      # Start matrix multiplication
    CMD_SEND_A = 0x02     # Send A matrix
    CMD_SEND_B = 0x03     # Send B matrix
    CMD_GET_RESULT = 0x04  # Request results

    def __init__(self, port: str, baudrate: int = 115200, timeout: float = 2.0):
        """Initialize UART connection"""
        self.ser = serial.Serial(port, baudrate=baudrate, timeout=timeout)
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()
        time.sleep(0.5)  # Wait for FPGA to stabilize
        print(f"Connected to {port} @ {baudrate} baud")

    def close(self):
        """Close serial connection"""
        if self.ser.is_open:
            self.ser.close()

    def send_command(self, cmd: int):
        """Send a command byte"""
        self.ser.write(bytes([cmd]))
        time.sleep(0.01)

    def send_matrix(self, matrix: List[List[int]], cmd: int = CMD_SEND_A):
        """
        Send a 4x4 matrix to FPGA
        Matrix is flattened to row-major order (16 bytes total)
        """
        self.send_command(cmd)
        time.sleep(0.05)

        flat = []
        for row in matrix:
            for val in row:
                # Ensure value fits in 8-bit signed range
                val = val & 0xFF
                flat.append(val)

        self.ser.write(bytes(flat))
        print(f"Sent {'A' if cmd == self.CMD_SEND_A else 'B'} matrix (16 bytes)")

    def receive_result(self) -> List[List[int]]:
        """
        Receive 4x4 result matrix from FPGA (64 bytes total, 4 bytes per element)
        Returns as list of lists with signed 32-bit integers
        """
        result = []
        for i in range(4):
            row = []
            for j in range(4):
                # Read 4 bytes in big-endian order
                bytes_data = self.ser.read(4)
                if len(bytes_data) < 4:
                    print(f"Error: Expected 4 bytes, got {len(bytes_data)}")
                    return None

                # Convert from big-endian to signed 32-bit int
                val = struct.unpack('>i', bytes_data)[0]
                row.append(val)

            result.append(row)

        return result

    def compute(self, a_matrix: List[List[int]], b_matrix: List[List[int]]) -> List[List[int]]:
        """
        Full computation sequence:
        1. Send A matrix
        2. Send B matrix
        3. Start computation
        4. Retrieve results
        """
        # Send matrices
        self.send_matrix(a_matrix, self.CMD_SEND_A)
        self.send_matrix(b_matrix, self.CMD_SEND_B)

        # Start computation
        self.send_command(self.CMD_START)
        print("Started computation")

        # Wait for results to be ready (systolic array takes ~15 cycles for 4x4)
        time.sleep(0.5)

        # Request and receive results
        self.send_command(self.CMD_GET_RESULT)
        print("Requesting results...")
        time.sleep(0.1)

        result = self.receive_result()
        return result

    @staticmethod
    def print_matrix(matrix: List[List[int]], name: str = "Matrix"):
        """Pretty print a matrix"""
        print(f"\n{name}:")
        for row in matrix:
            print("  " + " ".join(f"{val:8d}" for val in row))


def test_identity():
    """Test with identity × B"""
    print("=" * 60)
    print("Test 1: Identity × B (should get B as result)")
    print("=" * 60)

    a = [
        [1, 0, 0, 0],
        [0, 1, 0, 0],
        [0, 0, 1, 0],
        [0, 0, 0, 1]
    ]

    b = [
        [1, 2, 3, 4],
        [5, 6, 7, 8],
        [9, 10, 11, 12],
        [13, 14, 15, 16]
    ]

    BitSysHost.print_matrix(a, "A (Identity)")
    BitSysHost.print_matrix(b, "B")

    return a, b


def test_positive():
    """Test with positive integers"""
    print("=" * 60)
    print("Test 2: Positive Integer Matrices")
    print("=" * 60)

    a = [
        [1, 2, 0, 0],
        [2, 1, 0, 0],
        [0, 0, 1, 2],
        [0, 0, 2, 1]
    ]

    b = [
        [2, 1, 3, 2],
        [1, 2, 2, 3],
        [1, 1, 2, 1],
        [1, 1, 1, 2]
    ]

    BitSysHost.print_matrix(a, "A")
    BitSysHost.print_matrix(b, "B")

    return a, b


def test_mixed_sign():
    """Test with mixed positive and negative values"""
    print("=" * 60)
    print("Test 3: Mixed Sign Matrices")
    print("=" * 60)

    a = [
        [5, -3, 2, -1],
        [-2, 4, -1, 3],
        [1, -2, 4, -1],
        [-1, 1, -1, 2]
    ]

    b = [
        [3, -2, 1, 2],
        [2, 3, -1, 1],
        [-1, 2, 3, -2],
        [1, -1, 2, 3]
    ]

    BitSysHost.print_matrix(a, "A")
    BitSysHost.print_matrix(b, "B")

    return a, b


def verify_cpu(a: List[List[int]], b: List[List[int]]) -> List[List[int]]:
    """Verify result on CPU"""
    result = [[0] * 4 for _ in range(4)]

    for i in range(4):
        for j in range(4):
            for k in range(4):
                result[i][j] += a[i][k] * b[k][j]

    return result


def main():
    if len(sys.argv) < 2:
        print("Usage: python bitsys_host.py <COM_PORT> [test_number]")
        print("  test_number: 1=Identity, 2=Positive, 3=Mixed (default=1)")
        sys.exit(1)

    port = sys.argv[1]
    test_num = int(sys.argv[2]) if len(sys.argv) > 2 else 1

    # Select test case
    if test_num == 1:
        a, b = test_identity()
    elif test_num == 2:
        a, b = test_positive()
    elif test_num == 3:
        a, b = test_mixed_sign()
    else:
        print(f"Invalid test number: {test_num}")
        sys.exit(1)

    # Connect and run test
    try:
        host = BitSysHost(port)

        # Compute expected result
        expected = verify_cpu(a, b)
        BitSysHost.print_matrix(expected, "Expected Result (CPU)")

        # Send to FPGA and get result
        print("\n" + "=" * 60)
        print("Sending to FPGA...")
        print("=" * 60)

        result = host.compute(a, b)

        if result:
            BitSysHost.print_matrix(result, "FPGA Result")

            # Verify
            match = all(
                result[i][j] == expected[i][j]
                for i in range(4) for j in range(4)
            )

            if match:
                print("\n✓ PASS: Results match!")
            else:
                print("\n✗ FAIL: Results mismatch!")
                for i in range(4):
                    for j in range(4):
                        if result[i][j] != expected[i][j]:
                            print(f"  [{i}][{j}]: Expected {expected[i][j]}, Got {result[i][j]}")

        host.close()

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
