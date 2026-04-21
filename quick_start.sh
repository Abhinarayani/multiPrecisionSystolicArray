#!/bin/bash
# Quick Start: Build and Deploy to DE1-SoC
# Usage: bash quick_start.sh <STEP>
# Steps: setup, build, program, test

STEP=${1:-all}
PROJECT_DIR="quartus"
HOST_DIR="host"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}BitSys Systolic Array - DE1-SoC Quick Start${NC}\n"

# Step 1: Setup Quartus Project
setup_project() {
    echo -e "${BLUE}Step 1: Creating Quartus project...${NC}"
    cd "$PROJECT_DIR"
    
    if ! command -v quartus_sh &> /dev/null; then
        echo -e "${RED}Error: Quartus not found in PATH${NC}"
        echo "Please install Quartus and add to PATH"
        exit 1
    fi
    
    quartus_sh -t setup_project.tcl
    cd ..
    echo -e "${GREEN}✓ Project created: $PROJECT_DIR/bitsys_de1.qpf${NC}\n"
}

# Step 2: Build (compile) design
build_design() {
    echo -e "${BLUE}Step 2: Compiling design...${NC}"
    echo "This may take 5-10 minutes..."
    
    cd "$PROJECT_DIR"
    quartus_map bitsys_de1
    quartus_fit bitsys_de1
    quartus_asm bitsys_de1
    
    if [ -f "bitsys_de1.sof" ]; then
        echo -e "${GREEN}✓ Build successful: bitsys_de1.sof created${NC}\n"
        cd ..
    else
        echo -e "${RED}✗ Build failed!${NC}"
        echo "Check compilation messages above"
        exit 1
    fi
}

# Step 3: Program FPGA
program_fpga() {
    echo -e "${BLUE}Step 3: Programming FPGA...${NC}"
    echo "Make sure:"
    echo "  - USB-Blaster is connected to DE1-SoC"
    echo "  - DE1-SoC power is ON"
    
    read -p "Ready to program? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cd "$PROJECT_DIR"
        
        # Auto-detect programmer
        if quartus_pgm -l | grep -q "USB-Blaster"; then
            PROG_NAME="USB-Blaster [USB-0]"
        else
            PROG_NAME=$(quartus_pgm -l | grep -i blaster | head -1 | cut -d' ' -f1)
        fi
        
        if [ -z "$PROG_NAME" ]; then
            echo -e "${RED}Error: USB-Blaster not found${NC}"
            echo "Devices found:"
            quartus_pgm -l
            exit 1
        fi
        
        echo "Programming with: $PROG_NAME"
        quartus_pgm -c "$PROG_NAME" -m JTAG -o "P;bitsys_de1.sof"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ FPGA programmed successfully!${NC}\n"
            cd ..
        else
            echo -e "${RED}✗ Programming failed!${NC}"
            exit 1
        fi
    fi
}

# Step 4: Run host tests
run_tests() {
    echo -e "${BLUE}Step 4: Running host tests...${NC}"
    
    if ! python --version &> /dev/null; then
        echo -e "${RED}Error: Python not installed${NC}"
        exit 1
    fi
    
    # Check for pyserial
    if ! python -c "import serial" 2>/dev/null; then
        echo "Installing pyserial..."
        pip install pyserial
    fi
    
    cd "$HOST_DIR"
    
    echo "Available serial ports:"
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        # Windows
        mode
        read -p "Enter COM port (e.g., COM3): " PORT
    else
        # Linux/Mac
        ls /dev/tty*
        read -p "Enter port (e.g., /dev/ttyUSB0): " PORT
    fi
    
    echo -e "\n${GREEN}Running Test 1: Identity × B${NC}"
    python bitsys_host.py "$PORT" 1
    
    read -p "Run Test 2: Positive matrices? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Running Test 2: Positive matrices${NC}"
        python bitsys_host.py "$PORT" 2
    fi
    
    read -p "Run Test 3: Mixed sign matrices? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Running Test 3: Mixed sign matrices${NC}"
        python bitsys_host.py "$PORT" 3
    fi
    
    cd ..
    echo -e "${GREEN}✓ Testing complete!${NC}\n"
}

# Execute requested steps
case $STEP in
    setup)
        setup_project
        ;;
    build)
        build_design
        ;;
    program)
        program_fpga
        ;;
    test)
        run_tests
        ;;
    all)
        setup_project
        echo -e "${BLUE}Next: Run './quick_start.sh build' to compile${NC}\n"
        ;;
    *)
        echo "Usage: bash quick_start.sh [setup|build|program|test|all]"
        echo ""
        echo "Steps:"
        echo "  setup    - Create Quartus project"
        echo "  build    - Compile design (~5-10 min)"
        echo "  program  - Program FPGA"
        echo "  test     - Run host tests"
        echo "  all      - Setup only (then manually run others)"
        ;;
esac
