#!/bin/bash
# ==============================================================================
# Prerequisites Verification Script
# Checks all dependencies required for energy proportionality experiments
# ==============================================================================

set -u

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
WARN="${YELLOW}!${NC}"

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}        PREREQUISITES VERIFICATION                         ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"

ERRORS=0
WARNINGS=0

# ------------------------------------------------------------------------------
# Container Runtime (Docker or Podman)
# ------------------------------------------------------------------------------
echo -e "${BLUE}── Container Runtime ──${NC}\n"

RUNTIME_FOUND=false

# Podman
echo -n "  Podman........................ "
if command -v podman &>/dev/null; then
    VERSION=$(podman --version | grep -oP '\d+\.\d+' | head -1)
    echo -e "${PASS} v${VERSION}"
    RUNTIME_FOUND=true

    # Podman Compose
    echo -n "  Podman Compose................ "
    if command -v podman-compose &>/dev/null; then
        VERSION=$(podman-compose --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1 || echo "installed")
        echo -e "${PASS} v${VERSION}"
    else
        echo -e "${WARN} NOT INSTALLED"
        echo -e "      ${YELLOW}Fix: sudo apt-get install -y podman-compose${NC}"
    fi

    # Podman checkpoint support (native)
    echo -n "  Podman Checkpoint Support..... "
    if podman container checkpoint --help &>/dev/null; then
        echo -e "${PASS} Native support"
    else
        echo -e "${WARN} May require update"
    fi
else
    echo -e "${YELLOW}○${NC} NOT INSTALLED (optional if Docker available)"
fi

# Docker
echo -n "  Docker........................ "
if command -v docker &>/dev/null; then
    VERSION=$(docker --version | grep -oP '\d+\.\d+' | head -1)
    echo -e "${PASS} v${VERSION}"
    RUNTIME_FOUND=true

    # Docker Compose
    echo -n "  Docker Compose................ "
    if command -v docker-compose &>/dev/null; then
        VERSION=$(docker-compose --version | grep -oP '\d+\.\d+' | head -1)
        echo -e "${PASS} v${VERSION}"
    elif docker compose version &>/dev/null; then
        VERSION=$(docker compose version | grep -oP '\d+\.\d+' | head -1)
        echo -e "${PASS} v${VERSION} (plugin)"
    else
        echo -e "${WARN} NOT INSTALLED"
    fi

    # Docker Experimental
    echo -n "  Docker Experimental Mode...... "
    if docker info 2>/dev/null | grep -q "Experimental: true"; then
        echo -e "${PASS} Enabled"
    else
        echo -e "${WARN} DISABLED (required for Docker checkpoints)"
        echo -e "      ${YELLOW}Fix: Add {\"experimental\": true} to /etc/docker/daemon.json${NC}"
    fi
else
    echo -e "${YELLOW}○${NC} NOT INSTALLED (optional if Podman available)"
fi

# Check at least one runtime exists
if [ "$RUNTIME_FOUND" = false ]; then
    echo -e "\n  ${RED}ERROR: No container runtime found!${NC}"
    echo -e "  ${YELLOW}Install either Podman or Docker${NC}"
    ((ERRORS++))
fi

# ------------------------------------------------------------------------------
# Core Dependencies
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}── Core Dependencies ──${NC}\n"

# CRIU
echo -n "  CRIU.......................... "
if command -v criu &>/dev/null; then
    VERSION=$(criu --version 2>&1 | head -1 | grep -oP '\d+\.\d+' || echo "unknown")
    echo -e "${PASS} v${VERSION}"
else
    echo -e "${FAIL} NOT INSTALLED"
    echo -e "      ${YELLOW}Fix: sudo apt-get install -y criu${NC}"
    ((ERRORS++))
fi

# CRIU Functionality
echo -n "  CRIU Functionality Check...... "
if sudo criu check &>/dev/null; then
    echo -e "${PASS} OK"
else
    echo -e "${FAIL} FAILED"
    echo -e "      ${YELLOW}Run 'sudo criu check' for details${NC}"
    ((ERRORS++))
fi

# Python 3
echo -n "  Python 3...................... "
if command -v python3 &>/dev/null; then
    VERSION=$(python3 --version | grep -oP '\d+\.\d+')
    echo -e "${PASS} v${VERSION}"
else
    echo -e "${FAIL} NOT INSTALLED"
    ((ERRORS++))
fi

# ------------------------------------------------------------------------------
# System Utilities
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}── System Utilities ──${NC}\n"

# Netcat
echo -n "  Netcat (nc)................... "
if command -v nc &>/dev/null; then
    echo -e "${PASS} OK"
else
    echo -e "${FAIL} NOT INSTALLED"
    echo -e "      ${YELLOW}Fix: sudo apt-get install -y netcat${NC}"
    ((ERRORS++))
fi

# Numactl
echo -n "  Numactl....................... "
if command -v numactl &>/dev/null; then
    NODES=$(numactl --hardware 2>/dev/null | grep "available:" | awk '{print $2}')
    echo -e "${PASS} OK (${NODES} NUMA nodes)"
else
    echo -e "${WARN} NOT INSTALLED (optional)"
    echo -e "      ${YELLOW}Fix: sudo apt-get install -y numactl${NC}"
    ((WARNINGS++))
fi

# Turbostat
echo -n "  Turbostat..................... "
if command -v turbostat &>/dev/null; then
    echo -e "${PASS} OK"
else
    echo -e "${WARN} NOT INSTALLED (optional but recommended)"
    echo -e "      ${YELLOW}Fix: sudo apt-get install -y linux-tools-$(uname -r)${NC}"
    ((WARNINGS++))
fi

# ------------------------------------------------------------------------------
# Kernel Features
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}── Kernel Features ──${NC}\n"

# Kernel Version
echo -n "  Kernel Version................ "
KVER=$(uname -r)
KMAJOR=$(echo $KVER | cut -d. -f1)
KMINOR=$(echo $KVER | cut -d. -f2)
if [ "$KMAJOR" -ge 6 ] || ([ "$KMAJOR" -eq 5 ] && [ "$KMINOR" -ge 15 ]); then
    echo -e "${PASS} ${KVER}"
else
    echo -e "${WARN} ${KVER} (5.15+ recommended)"
    ((WARNINGS++))
fi

# Checkpoint/Restore Support
echo -n "  CONFIG_CHECKPOINT_RESTORE..... "
if grep -q "CONFIG_CHECKPOINT_RESTORE=y" /boot/config-$(uname -r) 2>/dev/null; then
    echo -e "${PASS} Enabled"
else
    echo -e "${FAIL} NOT ENABLED"
    ((ERRORS++))
fi

# C-states
echo -n "  CPU C-states.................. "
if [ -d /sys/devices/system/cpu/cpu0/cpuidle ]; then
    STATES=$(ls -d /sys/devices/system/cpu/cpu0/cpuidle/state* 2>/dev/null | wc -l)
    echo -e "${PASS} ${STATES} states available"
else
    echo -e "${FAIL} NOT AVAILABLE"
    ((ERRORS++))
fi

# C6 State
echo -n "  C6 Deep Sleep State........... "
C6_FOUND=false
for state in /sys/devices/system/cpu/cpu0/cpuidle/state*/name; do
    if [ -f "$state" ] && grep -qi "c6" "$state" 2>/dev/null; then
        C6_FOUND=true
        break
    fi
done
# Also check state3 as common C6 location
if [ -d /sys/devices/system/cpu/cpu0/cpuidle/state3 ]; then
    C6_FOUND=true
fi
if [ "$C6_FOUND" = true ]; then
    echo -e "${PASS} Available"
else
    echo -e "${WARN} NOT FOUND (check BIOS C-state settings)"
    ((WARNINGS++))
fi

# ------------------------------------------------------------------------------
# µSuite Requirements
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}── µSuite Requirements ──${NC}\n"

# Docker Image
echo -n "  µSuite Docker Image........... "
if docker images 2>/dev/null | grep -q "msuite-hdsearch"; then
    echo -e "${PASS} Found"
else
    echo -e "${FAIL} NOT FOUND"
    echo -e "      ${YELLOW}Build image using main MicroSuite instructions${NC}"
    ((ERRORS++))
fi

# Dataset
echo -n "  HDSearch Dataset.............. "
DATASET_PATHS=(
    "/home/shared_datasets/HDSearch/image_feature_vectors.dat"
    "/home/image_feature_vectors.dat"
    "$(pwd)/../image_feature_vectors.dat"
)
DATASET_FOUND=false
for path in "${DATASET_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SIZE=$(du -h "$path" | cut -f1)
        echo -e "${PASS} Found (${SIZE})"
        DATASET_FOUND=true
        break
    fi
done
if [ "$DATASET_FOUND" = false ]; then
    echo -e "${FAIL} NOT FOUND"
    echo -e "      ${YELLOW}Download from: https://akshithasriraman.eecs.umich.edu/dataset/HDSearch/${NC}"
    ((ERRORS++))
fi

# ------------------------------------------------------------------------------
# Permissions
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}── Permissions ──${NC}\n"

# Docker without sudo
echo -n "  Docker (non-root)............. "
if groups | grep -q docker; then
    echo -e "${PASS} User in docker group"
else
    echo -e "${WARN} User not in docker group"
    echo -e "      ${YELLOW}Fix: sudo usermod -aG docker \$USER && newgrp docker${NC}"
    ((WARNINGS++))
fi

# Sudo access
echo -n "  Sudo access................... "
if sudo -n true 2>/dev/null; then
    echo -e "${PASS} OK"
else
    echo -e "${WARN} Password required"
    ((WARNINGS++))
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                      SUMMARY                              ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "  ${GREEN}All prerequisites satisfied!${NC}"
    echo -e "  ${GREEN}Ready to run experiments.${NC}"
    EXIT_CODE=0
elif [ $ERRORS -eq 0 ]; then
    echo -e "  ${YELLOW}Warnings: ${WARNINGS}${NC}"
    echo -e "  ${GREEN}Core requirements satisfied. Optional components missing.${NC}"
    EXIT_CODE=0
else
    echo -e "  ${RED}Errors: ${ERRORS}${NC}"
    echo -e "  ${YELLOW}Warnings: ${WARNINGS}${NC}"
    echo -e "  ${RED}Please fix errors before running experiments.${NC}"
    EXIT_CODE=1
fi

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}\n"

exit $EXIT_CODE
