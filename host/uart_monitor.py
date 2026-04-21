#!/usr/bin/env python3
"""
Simple Serial Monitor for debugging BitSys UART communication
Displays raw bytes received and sent for protocol debugging.

Usage: python uart_monitor.py <PORT> [BAUDRATE]
Example: python uart_monitor.py COM3 115200
"""

import serial
import sys
import time
from datetime import datetime


class SerialMonitor:
    def __init__(self, port: str, baudrate: int = 115200):
        self.ser = serial.Serial(port, baudrate, timeout=1)
        print(f"Connected to {port} @ {baudrate} baud")
        print("Press Ctrl+C to exit\n")

    def monitor(self):
        """Monitor serial communication"""
        try:
            while True:
                # Check for incoming data
                if self.ser.in_waiting:
                    data = self.ser.read(self.ser.in_waiting)
                    timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
                    print(f"[{timestamp}] RX: {len(data)} bytes: {data.hex().upper()}")
                    # Try to interpret as ASCII
                    try:
                        ascii_text = data.decode('ascii', errors='ignore')
                        if ascii_text.strip():
                            print(f"         ASCII: {repr(ascii_text)}")
                    except:
                        pass

                time.sleep(0.01)

        except KeyboardInterrupt:
            print("\n\nMonitoring stopped.")
            self.ser.close()

    def interactive(self):
        """Interactive mode: send and receive"""
        try:
            while True:
                user_input = input("Enter hex bytes to send (e.g., '01 02 03') or 'q' to quit: ").strip()

                if user_input.lower() == 'q':
                    break

                try:
                    # Parse hex input
                    bytes_to_send = bytes.fromhex(user_input.replace(' ', ''))
                    self.ser.write(bytes_to_send)
                    print(f"TX: {bytes_to_send.hex().upper()}")

                    # Wait for response
                    time.sleep(0.1)
                    if self.ser.in_waiting:
                        response = self.ser.read(self.ser.in_waiting)
                        print(f"RX: {response.hex().upper()}")

                except ValueError as e:
                    print(f"Error parsing input: {e}")

        except KeyboardInterrupt:
            print("\n")
            self.ser.close()


def main():
    if len(sys.argv) < 2:
        print("UART Serial Monitor & Debugger")
        print("Usage: python uart_monitor.py <PORT> [BAUDRATE]")
        print("Example: python uart_monitor.py COM3 115200")
        sys.exit(1)

    port = sys.argv[1]
    baudrate = int(sys.argv[2]) if len(sys.argv) > 2 else 115200

    try:
        monitor = SerialMonitor(port, baudrate)

        print("Options:")
        print("  1 - Monitor (receive only)")
        print("  2 - Interactive (send & receive)")
        choice = input("Select mode (1-2): ").strip()

        if choice == "1":
            monitor.monitor()
        elif choice == "2":
            monitor.interactive()
        else:
            print("Invalid choice")

    except serial.SerialException as e:
        print(f"Serial error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
