#!/bin/bash
# ==============================================================================
# Container Restore Script
# Restores a container from checkpoint (simulating restore from disaggregated memory)
# Supports both Docker and Podman runtimes
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/detect_runtime.sh"

# Configuration
CONTAINER_NAME="${1:-hdsearch_midtier}"
CHECKPOINT_NAME="${2}"
CHECKPOINT_DIR="${3:-/tmp/checkpoints}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Validate inputs
if [ -z "${CHECKPOINT_NAME}" ]; then
    log_error "Usage: $0 <container_name> <checkpoint_name> [checkpoint_dir]"
    log_error "Example: $0 hdsearch_midtier hdsearch_midtier_20241218_120000"
    exit 1
fi

# Detect runtime
RUNTIME=$(detect_runtime)
if [ "$RUNTIME" = "none" ]; then
    log_error "No container runtime found (Docker or Podman)"
    exit 1
fi
log_info "Using runtime: ${RUNTIME}"

# Validate checkpoint exists
case "$RUNTIME" in
    podman)
        CHECKPOINT_FILE="${CHECKPOINT_DIR}/${CHECKPOINT_NAME}.tar.gz"
        if [ ! -f "${CHECKPOINT_FILE}" ]; then
            log_error "Checkpoint not found: ${CHECKPOINT_FILE}"
            exit 1
        fi
        ;;
    docker)
        if [ ! -d "${CHECKPOINT_DIR}/${CHECKPOINT_NAME}" ]; then
            log_error "Checkpoint not found: ${CHECKPOINT_DIR}/${CHECKPOINT_NAME}"
            exit 1
        fi
        ;;
esac

log_info "Restoring container: ${CONTAINER_NAME}"
log_info "From checkpoint: ${CHECKPOINT_NAME}"
log_info "Checkpoint directory: ${CHECKPOINT_DIR}"

# Record start time for latency measurement
START_TIME=$(date +%s%N)

# Restore container based on runtime
case "$RUNTIME" in
    podman)
        # Podman restore syntax
        CHECKPOINT_FILE="${CHECKPOINT_DIR}/${CHECKPOINT_NAME}.tar.gz"

        # For Podman, we need to restore to a new container or the same name
        # Check if container exists (stopped)
        if podman ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            log_info "Restoring existing container..."
            podman container restore \
                --import="${CHECKPOINT_FILE}" \
                --name="${CONTAINER_NAME}" \
                --ignore-static-ip \
                --ignore-static-mac 2>/dev/null || \
            podman container restore \
                --import="${CHECKPOINT_FILE}"
        else
            log_info "Restoring as new container..."
            podman container restore \
                --import="${CHECKPOINT_FILE}" \
                --name="${CONTAINER_NAME}"
        fi
        ;;

    docker)
        # Docker restore syntax - start with checkpoint
        docker start \
            --checkpoint="${CHECKPOINT_NAME}" \
            --checkpoint-dir="${CHECKPOINT_DIR}" \
            "${CONTAINER_NAME}"
        ;;
esac

# Record end time
END_TIME=$(date +%s%N)

# Calculate latency in milliseconds
RESTORE_LATENCY_MS=$(( (END_TIME - START_TIME) / 1000000 ))

# Verify container is running
sleep 1
case "$RUNTIME" in
    podman)
        RUNNING=$(podman ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" && echo "yes" || echo "no")
        ;;
    docker)
        RUNNING=$(docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" && echo "yes" || echo "no")
        ;;
esac

if [ "$RUNNING" = "yes" ]; then
    log_info "Container restored successfully"
    log_info "  Runtime: ${RUNTIME}"
    log_info "  Restore latency: ${RESTORE_LATENCY_MS} ms"
else
    log_error "Container failed to restore"
    exit 1
fi

# Write metrics to file for analysis
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
METRICS_FILE="${CHECKPOINT_DIR}/restore_metrics.csv"
if [ ! -f "${METRICS_FILE}" ]; then
    echo "timestamp,runtime,container,checkpoint_name,latency_ms" > "${METRICS_FILE}"
fi
echo "${TIMESTAMP},${RUNTIME},${CONTAINER_NAME},${CHECKPOINT_NAME},${RESTORE_LATENCY_MS}" >> "${METRICS_FILE}"

log_info "Container is now running and ready to serve requests"

echo "${RESTORE_LATENCY_MS}"
