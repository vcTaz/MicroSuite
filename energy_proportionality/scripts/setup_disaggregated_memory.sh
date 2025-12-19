#!/bin/bash
# ==============================================================================
# Setup Disaggregated Memory Simulation
# Creates a tmpfs mount to simulate CXL/disaggregated memory for checkpoints
# Uses NUMA remote memory when available for realistic latency characteristics
# ==============================================================================

set -e

# Configuration
CHECKPOINT_MOUNT="${1:-/mnt/disaggregated_memory}"
MEMORY_SIZE="${2:-8G}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root (sudo)"
    exit 1
fi

log_section "Setting Up Disaggregated Memory Simulation"

# Check NUMA topology
log_info "Checking NUMA topology..."
if command -v numactl &> /dev/null; then
    NUMA_NODES=$(numactl --hardware 2>/dev/null | grep "available:" | awk '{print $2}')
    log_info "NUMA nodes available: ${NUMA_NODES}"

    if [ "${NUMA_NODES}" -gt 1 ]; then
        log_info "Multi-NUMA system detected - will use remote NUMA node for realistic latency"
        USE_NUMA=true
        # Use the last NUMA node as "remote" memory
        REMOTE_NODE=$((NUMA_NODES - 1))
    else
        log_warn "Single NUMA node - using local memory (latency won't reflect true disaggregation)"
        USE_NUMA=false
    fi
else
    log_warn "numactl not installed - cannot optimize for NUMA"
    USE_NUMA=false
fi

# Create mount point
log_info "Creating mount point: ${CHECKPOINT_MOUNT}"
mkdir -p "${CHECKPOINT_MOUNT}"

# Unmount if already mounted
if mountpoint -q "${CHECKPOINT_MOUNT}"; then
    log_warn "Unmounting existing mount..."
    umount "${CHECKPOINT_MOUNT}"
fi

# Mount tmpfs with appropriate NUMA policy
if [ "${USE_NUMA}" = true ]; then
    log_info "Mounting tmpfs on NUMA node ${REMOTE_NODE} (size: ${MEMORY_SIZE})..."
    mount -t tmpfs \
        -o size=${MEMORY_SIZE},mpol=bind:${REMOTE_NODE} \
        tmpfs "${CHECKPOINT_MOUNT}"
else
    log_info "Mounting tmpfs (size: ${MEMORY_SIZE})..."
    mount -t tmpfs \
        -o size=${MEMORY_SIZE} \
        tmpfs "${CHECKPOINT_MOUNT}"
fi

# Set permissions
chmod 777 "${CHECKPOINT_MOUNT}"

# Verify mount
if mountpoint -q "${CHECKPOINT_MOUNT}"; then
    log_info "Disaggregated memory simulation ready"
    log_info "  Mount point: ${CHECKPOINT_MOUNT}"
    log_info "  Size: ${MEMORY_SIZE}"

    # Show memory info
    df -h "${CHECKPOINT_MOUNT}"

    if [ "${USE_NUMA}" = true ]; then
        log_info "  NUMA node: ${REMOTE_NODE} (remote)"
        log_info "  Expected additional latency: ~100-300ns (simulating CXL)"
    fi
else
    log_error "Failed to mount disaggregated memory"
    exit 1
fi

log_section "Configuration for Experiments"
echo "export CHECKPOINT_DIR=${CHECKPOINT_MOUNT}"
echo ""
log_info "Add the above export to your shell or pass to experiment scripts"

# Create a config file
CONFIG_FILE="${CHECKPOINT_MOUNT}/.config"
cat > "${CONFIG_FILE}" << EOF
# Disaggregated Memory Configuration
CHECKPOINT_MOUNT=${CHECKPOINT_MOUNT}
MEMORY_SIZE=${MEMORY_SIZE}
USE_NUMA=${USE_NUMA}
NUMA_NODE=${REMOTE_NODE:-0}
CREATED=$(date -Iseconds)
EOF

log_info "Configuration saved to ${CONFIG_FILE}"
