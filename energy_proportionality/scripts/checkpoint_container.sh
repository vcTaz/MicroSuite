#!/bin/bash
# ==============================================================================
# Container Checkpoint Script
# Checkpoints a running container to simulate snapshotting to disaggregated memory
# Supports both Docker and Podman runtimes
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/detect_runtime.sh"

# Configuration
CONTAINER_NAME="${1:-hdsearch_midtier}"
CHECKPOINT_DIR="${2:-/tmp/checkpoints}"
LEAVE_RUNNING="${3:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect runtime
RUNTIME=$(detect_runtime)
if [ "$RUNTIME" = "none" ]; then
    log_error "No container runtime found (Docker or Podman)"
    exit 1
fi
log_info "Using runtime: ${RUNTIME}"

# Check checkpoint support
CKPT_SUPPORT=$(check_checkpoint_support "$RUNTIME")
if [ "$CKPT_SUPPORT" = "requires_experimental" ]; then
    log_error "Docker experimental mode not enabled"
    log_error "Add {\"experimental\": true} to /etc/docker/daemon.json"
    exit 1
elif [ "$CKPT_SUPPORT" = "unsupported" ]; then
    log_error "Checkpoint not supported on this runtime"
    exit 1
fi

# Validate container exists and is running
case "$RUNTIME" in
    podman)
        if ! podman ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            log_error "Container '${CONTAINER_NAME}' is not running"
            exit 1
        fi
        ;;
    docker)
        if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            log_error "Container '${CONTAINER_NAME}' is not running"
            exit 1
        fi
        ;;
esac

# Create checkpoint directory
mkdir -p "${CHECKPOINT_DIR}"

# Generate checkpoint name with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CHECKPOINT_NAME="${CONTAINER_NAME}_${TIMESTAMP}"

log_info "Creating checkpoint for container: ${CONTAINER_NAME}"
log_info "Checkpoint directory: ${CHECKPOINT_DIR}"
log_info "Checkpoint name: ${CHECKPOINT_NAME}"

# Record start time for latency measurement
START_TIME=$(date +%s%N)

# Create checkpoint based on runtime
case "$RUNTIME" in
    podman)
        # Podman checkpoint syntax
        CHECKPOINT_FILE="${CHECKPOINT_DIR}/${CHECKPOINT_NAME}.tar.gz"

        if [ "${LEAVE_RUNNING}" = "true" ]; then
            log_info "Creating checkpoint (leaving container running)..."
            podman container checkpoint \
                --export="${CHECKPOINT_FILE}" \
                --keep \
                "${CONTAINER_NAME}"
        else
            log_info "Creating checkpoint (stopping container)..."
            podman container checkpoint \
                --export="${CHECKPOINT_FILE}" \
                "${CONTAINER_NAME}"
        fi
        ;;

    docker)
        # Docker checkpoint syntax
        if [ "${LEAVE_RUNNING}" = "true" ]; then
            log_info "Creating checkpoint (leaving container running)..."
            docker checkpoint create \
                --checkpoint-dir="${CHECKPOINT_DIR}" \
                --leave-running \
                "${CONTAINER_NAME}" \
                "${CHECKPOINT_NAME}"
        else
            log_info "Creating checkpoint (stopping container)..."
            docker checkpoint create \
                --checkpoint-dir="${CHECKPOINT_DIR}" \
                "${CONTAINER_NAME}" \
                "${CHECKPOINT_NAME}"
        fi
        ;;
esac

# Record end time
END_TIME=$(date +%s%N)

# Calculate latency in milliseconds
CHECKPOINT_LATENCY_MS=$(( (END_TIME - START_TIME) / 1000000 ))

# Get checkpoint size
case "$RUNTIME" in
    podman)
        CHECKPOINT_SIZE=$(du -sh "${CHECKPOINT_FILE}" 2>/dev/null | cut -f1 || echo "N/A")
        ;;
    docker)
        CHECKPOINT_SIZE=$(du -sh "${CHECKPOINT_DIR}/${CHECKPOINT_NAME}" 2>/dev/null | cut -f1 || echo "N/A")
        ;;
esac

# Output results
log_info "Checkpoint created successfully"
log_info "  Runtime: ${RUNTIME}"
log_info "  Latency: ${CHECKPOINT_LATENCY_MS} ms"
log_info "  Size: ${CHECKPOINT_SIZE}"

# Write metrics to file for analysis
METRICS_FILE="${CHECKPOINT_DIR}/checkpoint_metrics.csv"
if [ ! -f "${METRICS_FILE}" ]; then
    echo "timestamp,runtime,container,checkpoint_name,latency_ms,size" > "${METRICS_FILE}"
fi
echo "${TIMESTAMP},${RUNTIME},${CONTAINER_NAME},${CHECKPOINT_NAME},${CHECKPOINT_LATENCY_MS},${CHECKPOINT_SIZE}" >> "${METRICS_FILE}"

# If container was stopped, it can now enter C6 state
if [ "${LEAVE_RUNNING}" != "true" ]; then
    log_info "Container stopped - CPU can enter deep C-state (C6)"
    log_info "To restore: ./restore_container.sh ${CONTAINER_NAME} ${CHECKPOINT_NAME}"
fi

echo "${CHECKPOINT_NAME}"
