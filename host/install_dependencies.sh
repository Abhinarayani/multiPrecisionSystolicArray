#!/usr/bin/env bash
# Installation script for BitSys host dependencies

echo "Installing BitSys Host Dependencies..."
echo "======================================"

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    if ! command -v python &> /dev/null; then
        echo "ERROR: Python not found!"
        echo "Please install Python 3.6+ from https://www.python.org/"
        exit 1
    fi
    PYTHON_CMD="python"
else
    PYTHON_CMD="python3"
fi

echo "Found Python: $($PYTHON_CMD --version)"

# Try to install pyserial
echo ""
echo "Installing pyserial..."

# Try pip3 first
if command -v pip3 &> /dev/null; then
    pip3 install pyserial
elif command -v pip &> /dev/null; then
    pip install pyserial
else
    # Try python -m pip
    $PYTHON_CMD -m pip install pyserial
fi

# Verify installation
echo ""
echo "Verifying installation..."
$PYTHON_CMD -c "import serial; print(f'✓ pyserial {serial.__version__} installed successfully!')" 2>/dev/null

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Installation complete!"
    echo "You can now run: python bitsys_host.py COM3 1"
else
    echo ""
    echo "✗ Installation may have failed."
    echo "Try manual installation:"
    echo "  Windows: py -m pip install pyserial"
    echo "  Linux/Mac: python3 -m pip install pyserial"
fi
