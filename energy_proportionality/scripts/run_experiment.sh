#!/bin/bash
# ==============================================================================
# Energy Proportionality Experiment Runner
# Main script for investigating resource disaggregation and container snapshotting
# Supports both Docker and Podman runtimes
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${PROJECT_DIR}/configs"
RESULTS_DIR="${PROJECT_DIR}/results"

# Source runtime detection
source "${SCRIPT_DIR}/detect_runtime.sh"

# Configuration
EXPERIMENT_NAME="${1:-experiment}"
NUM_RUNS="${2:-10}"
CHECKPOINT_DIR="${3:-/tmp/checkpoints}"
IDLE_DURATION="${4:-5}"  # Seconds to idle between bursts

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}========================================${NC}"; }

# Detect runtime
RUNTIME=$(detect_runtime)
if [ "$RUNTIME" = "none" ]; then
    log_error "No container runtime found (Docker or Podman)"
    exit 1
fi

COMPOSE_CMD=$(get_compose_command "$RUNTIME")

# Create results directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RUN_DIR="${RESULTS_DIR}/${EXPERIMENT_NAME}_${TIMESTAMP}"
mkdir -p "${RUN_DIR}"

# Initialize results file
RESULTS_FILE="${RUN_DIR}/results.csv"
echo "run,phase,checkpoint_ms,restore_ms,idle_duration_s,c6_residency_percent" > "${RESULTS_FILE}"

log_section "Energy Proportionality Experiment"
log_info "Experiment: ${EXPERIMENT_NAME}"
log_info "Number of runs: ${NUM_RUNS}"
log_info "Checkpoint directory: ${CHECKPOINT_DIR}"
log_info "Idle duration: ${IDLE_DURATION}s"
log_info "Results directory: ${RUN_DIR}"

# Check prerequisites
log_section "Checking Prerequisites"

# Check runtime
log_info "Container Runtime: ${RUNTIME}"
log_info "Compose Command: ${COMPOSE_CMD}"

# Check checkpoint support
CKPT_SUPPORT=$(check_checkpoint_support "$RUNTIME")
if [ "$CKPT_SUPPORT" = "supported" ]; then
    log_info "Checkpoint Support: OK"
elif [ "$CKPT_SUPPORT" = "requires_experimental" ]; then
    log_error "Docker experimental features not enabled"
    log_error "Add {\"experimental\": true} to /etc/docker/daemon.json"
    exit 1
else
    log_error "Checkpoint not supported"
    exit 1
fi

# Check CRIU
if command -v criu &> /dev/null; then
    log_info "CRIU: $(criu --version 2>&1 | head -1)"
else
    log_warn "CRIU not found - checkpoint may fail"
fi

# Check turbostat
if command -v turbostat &> /dev/null; then
    log_info "turbostat: Available"
    USE_TURBOSTAT=true
else
    log_warn "turbostat not found - using C6 sysfs monitoring instead"
    USE_TURBOSTAT=false
fi

# Create checkpoint directory
mkdir -p "${CHECKPOINT_DIR}"
log_info "Checkpoint directory ready: ${CHECKPOINT_DIR}"

# Start experiment
log_section "Starting Baseline (No Checkpointing)"

cd "${CONFIG_DIR}"

# Clean up any existing containers
${COMPOSE_CMD} -f docker-compose-checkpoint.yml down 2>/dev/null || true

# Run baseline without checkpointing
log_info "Running baseline experiment..."

# Start C6 monitoring in background
"${SCRIPT_DIR}/monitor_c6_state.sh" "0,2,4" 1 "${RUN_DIR}/baseline_c6.csv" $((30 + IDLE_DURATION * 2)) &
C6_MONITOR_PID=$!

# Start turbostat if available
if [ "$USE_TURBOSTAT" = true ]; then
    sudo turbostat --cpu 0,2,4 --interval 1 --out "${RUN_DIR}/baseline_turbostat.log" &
    TURBOSTAT_PID=$!
fi

# Start services
export CHECKPOINT_DIR
${COMPOSE_CMD} -f docker-compose-checkpoint.yml up -d

# Wait for client to finish
log_info "Waiting for baseline run to complete..."
if [ "$RUNTIME" = "podman" ]; then
    podman logs -f hdsearch_client 2>&1 | tee "${RUN_DIR}/baseline_client.log" | grep -m 1 "finished" || sleep 35
else
    docker logs -f hdsearch_client 2>&1 | tee "${RUN_DIR}/baseline_client.log" | grep -m 1 "finished" || sleep 35
fi

# Stop monitoring
kill $C6_MONITOR_PID 2>/dev/null || true
[ "$USE_TURBOSTAT" = true ] && sudo kill $TURBOSTAT_PID 2>/dev/null || true

# Collect logs
if [ "$RUNTIME" = "podman" ]; then
    podman logs hdsearch_bucket > "${RUN_DIR}/baseline_bucket.log" 2>&1
    podman logs hdsearch_midtier > "${RUN_DIR}/baseline_midtier.log" 2>&1
else
    docker logs hdsearch_bucket > "${RUN_DIR}/baseline_bucket.log" 2>&1
    docker logs hdsearch_midtier > "${RUN_DIR}/baseline_midtier.log" 2>&1
fi

# Clean up
${COMPOSE_CMD} -f docker-compose-checkpoint.yml down

log_info "Baseline complete"

# Run checkpoint experiments
log_section "Running Checkpoint Experiments"

for run in $(seq 1 $NUM_RUNS); do
    log_info "--- Run ${run}/${NUM_RUNS} ---"

    # Start services
    ${COMPOSE_CMD} -f docker-compose-checkpoint.yml up -d bucket midtier

    # Wait for services to be ready
    sleep 5

    # Start C6 monitoring
    "${SCRIPT_DIR}/monitor_c6_state.sh" "0,2,4" 1 "${RUN_DIR}/run${run}_c6.csv" $((30 + IDLE_DURATION * 3)) &
    C6_MONITOR_PID=$!

    if [ "$USE_TURBOSTAT" = true ]; then
        sudo turbostat --cpu 0,2,4 --interval 1 --out "${RUN_DIR}/run${run}_turbostat.log" &
        TURBOSTAT_PID=$!
    fi

    # Phase 1: Initial load burst
    log_info "Phase 1: Initial load burst"
    ${COMPOSE_CMD} -f docker-compose-checkpoint.yml up -d client
    if [ "$RUNTIME" = "podman" ]; then
        podman logs -f hdsearch_client 2>&1 | grep -m 1 "finished" || sleep 35
    else
        docker logs -f hdsearch_client 2>&1 | grep -m 1 "finished" || sleep 35
    fi
    ${COMPOSE_CMD} -f docker-compose-checkpoint.yml stop client

    # Phase 2: Checkpoint midtier (simulating snapshot to disaggregated memory)
    log_info "Phase 2: Checkpointing midtier..."
    CHECKPOINT_START=$(date +%s%N)

    CHECKPOINT_NAME="midtier_run${run}_${TIMESTAMP}"

    if [ "$RUNTIME" = "podman" ]; then
        if podman container checkpoint \
            --export="${CHECKPOINT_DIR}/${CHECKPOINT_NAME}.tar.gz" \
            hdsearch_midtier 2>"${RUN_DIR}/run${run}_checkpoint_error.log"; then
            CHECKPOINT_END=$(date +%s%N)
            CHECKPOINT_MS=$(( (CHECKPOINT_END - CHECKPOINT_START) / 1000000 ))
            log_info "Checkpoint created in ${CHECKPOINT_MS}ms"
        else
            log_error "Checkpoint failed - see ${RUN_DIR}/run${run}_checkpoint_error.log"
            CHECKPOINT_MS=-1
        fi
    else
        if docker checkpoint create \
            --checkpoint-dir="${CHECKPOINT_DIR}" \
            hdsearch_midtier \
            "${CHECKPOINT_NAME}" 2>"${RUN_DIR}/run${run}_checkpoint_error.log"; then
            CHECKPOINT_END=$(date +%s%N)
            CHECKPOINT_MS=$(( (CHECKPOINT_END - CHECKPOINT_START) / 1000000 ))
            log_info "Checkpoint created in ${CHECKPOINT_MS}ms"
        else
            log_error "Checkpoint failed - see ${RUN_DIR}/run${run}_checkpoint_error.log"
            CHECKPOINT_MS=-1
        fi
    fi

    # Phase 3: Idle period (CPU should enter C6)
    log_info "Phase 3: Idle period (${IDLE_DURATION}s) - measuring C6 residency"
    sleep ${IDLE_DURATION}

    # Phase 4: Restore midtier
    log_info "Phase 4: Restoring midtier..."
    RESTORE_START=$(date +%s%N)

    if [ "$RUNTIME" = "podman" ]; then
        if podman container restore \
            --import="${CHECKPOINT_DIR}/${CHECKPOINT_NAME}.tar.gz" \
            --name=hdsearch_midtier 2>"${RUN_DIR}/run${run}_restore_error.log"; then
            RESTORE_END=$(date +%s%N)
            RESTORE_MS=$(( (RESTORE_END - RESTORE_START) / 1000000 ))
            log_info "Restored in ${RESTORE_MS}ms"
        else
            log_error "Restore failed - see ${RUN_DIR}/run${run}_restore_error.log"
            RESTORE_MS=-1
        fi
    else
        if docker start \
            --checkpoint="${CHECKPOINT_NAME}" \
            --checkpoint-dir="${CHECKPOINT_DIR}" \
            hdsearch_midtier 2>"${RUN_DIR}/run${run}_restore_error.log"; then
            RESTORE_END=$(date +%s%N)
            RESTORE_MS=$(( (RESTORE_END - RESTORE_START) / 1000000 ))
            log_info "Restored in ${RESTORE_MS}ms"
        else
            log_error "Restore failed - see ${RUN_DIR}/run${run}_restore_error.log"
            RESTORE_MS=-1
        fi
    fi

    # Phase 5: Second load burst after restore
    log_info "Phase 5: Post-restore load burst"
    ${COMPOSE_CMD} -f docker-compose-checkpoint.yml up -d client
    if [ "$RUNTIME" = "podman" ]; then
        podman logs -f hdsearch_client 2>&1 | grep -m 1 "finished" || sleep 35
    else
        docker logs -f hdsearch_client 2>&1 | grep -m 1 "finished" || sleep 35
    fi

    # Stop monitoring
    kill $C6_MONITOR_PID 2>/dev/null || true
    [ "$USE_TURBOSTAT" = true ] && sudo kill $TURBOSTAT_PID 2>/dev/null || true

    # Calculate average C6 residency during idle
    C6_RESIDENCY=$(tail -n +2 "${RUN_DIR}/run${run}_c6.csv" | awk -F',' '
        BEGIN { sum=0; count=0 }
        { for(i=5; i<=NF; i+=3) { sum+=$i; count++ } }
        END { if(count>0) printf "%.2f", sum/count; else print "0" }
    ')

    # Record results
    echo "${run},checkpoint,${CHECKPOINT_MS},${RESTORE_MS},${IDLE_DURATION},${C6_RESIDENCY}" >> "${RESULTS_FILE}"

    # Collect logs
    if [ "$RUNTIME" = "podman" ]; then
        podman logs hdsearch_bucket > "${RUN_DIR}/run${run}_bucket.log" 2>&1
        podman logs hdsearch_midtier > "${RUN_DIR}/run${run}_midtier.log" 2>&1
        podman logs hdsearch_client > "${RUN_DIR}/run${run}_client.log" 2>&1
    else
        docker logs hdsearch_bucket > "${RUN_DIR}/run${run}_bucket.log" 2>&1
        docker logs hdsearch_midtier > "${RUN_DIR}/run${run}_midtier.log" 2>&1
        docker logs hdsearch_client > "${RUN_DIR}/run${run}_client.log" 2>&1
    fi

    # Clean up
    ${COMPOSE_CMD} -f docker-compose-checkpoint.yml down

    log_info "Run ${run} complete: checkpoint=${CHECKPOINT_MS}ms, restore=${RESTORE_MS}ms, C6=${C6_RESIDENCY}%"
done

# Generate summary
log_section "Experiment Complete"

log_info "Results saved to: ${RUN_DIR}"
log_info "Summary:"

# Calculate statistics
awk -F',' '
NR > 1 {
    if ($3 > 0) { ckpt_sum += $3; ckpt_count++ }
    if ($4 > 0) { rest_sum += $4; rest_count++ }
    c6_sum += $6; c6_count++
}
END {
    printf "  Average Checkpoint Time: %.1f ms\n", (ckpt_count > 0 ? ckpt_sum/ckpt_count : 0)
    printf "  Average Restore Time: %.1f ms\n", (rest_count > 0 ? rest_sum/rest_count : 0)
    printf "  Average C6 Residency: %.2f%%\n", (c6_count > 0 ? c6_sum/c6_count : 0)
}' "${RESULTS_FILE}"

log_info "Run analysis script for detailed results:"
log_info "  python3 ${SCRIPT_DIR}/../analysis/analyze_results.py ${RUN_DIR}"
