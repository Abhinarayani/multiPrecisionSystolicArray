@echo off
REM Installation script for BitSys host dependencies (Windows)

echo.
echo Installing BitSys Host Dependencies...
echo ======================================
echo.

REM Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python not found in PATH!
    echo.
    echo Please:
    echo 1. Install Python 3.6+ from https://www.python.org/
    echo 2. Make sure to check "Add Python to PATH" during installation
    echo 3. Restart this terminal
    pause
    exit /b 1
)

echo Python version:
python --version

REM Install pyserial
echo.
echo Installing pyserial...
echo.

python -m pip install --upgrade pip
python -m pip install pyserial

REM Verify installation
echo.
echo Verifying installation...
python -c "import serial; print(f'pyserial {serial.__version__} installed successfully!')" 2>nul

if %errorlevel% equ 0 (
    echo.
    echo [OK] Installation complete!
    echo.
    echo Next steps:
    echo 1. Connect USB-to-UART bridge to DE1-SoC
    echo 2. Program FPGA with bitsys_de1.sof
    echo 3. Find COM port in Device Manager
    echo 4. Run: python bitsys_host.py COM3 1
    echo.
) else (
    echo.
    echo [ERROR] Installation may have failed.
    echo.
    echo Try manual installation:
    echo   python -m pip install pyserial
    echo.
    echo If that fails, try:
    echo   py -m pip install pyserial
    echo.
)

pause
