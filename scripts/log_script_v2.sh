#!/bin/bash
# ==============================================================================
# iutomation Script (V2 - Per-Service Monitoring)
#
# This script automates running HDSearch microservices, monitors each service's
# dedicated CPU with turbostat, and collects logs into numbered run files.
# ==============================================================================

# --- Configuration ---
COMPOSE_FILE="docker-compose-hdsearch-split.yml"
MAIN_LOG_FILE="experiment_run.log"

# NEW: Define directories for measurements
BUCKET_DIR="bucket_measurements"
MIDTIER_DIR="midtier_measurements"
CLIENT_DIR="client_measurements"

# NEW: Define CPUs for each service (from your docker-compose file)
BUCKET_CPU='0'
MIDTIER_CPU='2'
CLIENT_CPU='4'

# --- Helper function for logging with timestamps ---
log() {
    # This function prints a message to both the console and the main log file.
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$MAIN_LOG_FILE"
}

# --- NEW: Helper function to get the next run number ---
get_next_run_number() {
    local dir="$1"
    local prefix="$2"
    # Count how many files with the given prefix already exist in the directory
    local count=$(ls -1 "${dir}/${prefix}"*.log 2>/dev/null | wc -l)
    echo $((count + 1))
}

# --- Main Script ---

# 1. Initial Setup
# -----------------
# Clear the main log file for a fresh run.
> "$MAIN_LOG_FILE"

log ">>> Starting Experiment <<<"
log "Performing initial cleanup of Docker environment..."
docker-compose -f "$COMPOSE_FILE" down
log "Docker cleanup complete."

# NEW: Create measurement directories if they don't exist
log "Ensuring measurement directories exist..."
mkdir -p "$BUCKET_DIR" "$MIDTIER_DIR" "$CLIENT_DIR"
log "Directories are ready."
echo "----------------------------------------------------" | tee -a "$MAIN_LOG_FILE"

# 2. Start Per-Service Turbostat Monitoring
# -----------------------------------------
log "Starting turbostat for each service..."

# NEW: Determine the run number for this experiment
RUN_NUMBER=$(get_next_run_number "$BUCKET_DIR" "bucket_turbostat_")
log "This is experiment run number: $RUN_NUMBER"

# NEW: Launch turbostat for the 'bucket' service
TURBOSTAT_LOG_BUCKET="${BUCKET_DIR}/bucket_turbostat_${RUN_NUMBER}.log"
sudo turbostat --cpu "$BUCKET_CPU" --interval 5 --out "$TURBOSTAT_LOG_BUCKET" &
BUCKET_TURBOSTAT_PID=$!
log "Turbostat for bucket (CPU ${BUCKET_CPU}) running with PID: $BUCKET_TURBOSTAT_PID"

# NEW: Launch turbostat for the 'midtier' service
TURBOSTAT_LOG_MIDTIER="${MIDTIER_DIR}/midtier_turbostat_${RUN_NUMBER}.log"
sudo turbostat --cpu "$MIDTIER_CPU" --interval 5 --out "$TURBOSTAT_LOG_MIDTIER" &
MIDTIER_TURBOSTAT_PID=$!
log "Turbostat for midtier (CPU ${MIDTIER_CPU}) running with PID: $MIDTIER_TURBOSTAT_PID"

# NEW: Launch turbostat for the 'client' service
TURBOSTAT_LOG_CLIENT="${CLIENT_DIR}/client_turbostat_${RUN_NUMBER}.log"
sudo turbostat --cpu "$CLIENT_CPU" --interval 5 --out "$TURBOSTAT_LOG_CLIENT" &
CLIENT_TURBOSTAT_PID=$!
log "Turbostat for client (CPU ${CLIENT_CPU}) running with PID: $CLIENT_TURBOSTAT_PID"
echo "----------------------------------------------------" | tee -a "$MAIN_LOG_FILE"


# 3. Launch Microservices Sequentially
# ------------------------------------
log "Launching 'bucket' service on CPU $BUCKET_CPU..."
docker-compose -f "$COMPOSE_FILE" up -d bucket
log "'bucket' service started."
sleep 5

log "Launching 'midtier' service on CPU $MIDTIER_CPU..."
docker-compose -f "$COMPOSE_FILE" up -d midtier
log "'midtier' service started."
sleep 5

log "Launching 'client' service on CPU $CLIENT_CPU to generate load..."
docker-compose -f "$COMPOSE_FILE" up -d client
log "'client' service started. Now waiting for it to finish."
echo "----------------------------------------------------" | tee -a "$MAIN_LOG_FILE"


# 4. Wait for Client to Finish
# ----------------------------
docker logs -f hdsearch_client | grep -m 1 "Load generator finished" &
wait $!
log "Client has finished its load generation task."
echo "----------------------------------------------------" | tee -a "$MAIN_LOG_FILE"


# 5. Stop Turbostat and Collect Logs
# ----------------------------------
log "Stopping all turbostat processes..."
# MODIFIED: Stop all three turbostat instances
sudo kill $BUCKET_TURBOSTAT_PID $MIDTIER_TURBOSTAT_PID $CLIENT_TURBOSTAT_PID
wait $BUCKET_TURBOSTAT_PID 2>/dev/null
wait $MIDTIER_TURBOSTAT_PID 2>/dev/null
wait $CLIENT_TURBOSTAT_PID 2>/dev/null
log "All turbostat processes stopped."

log "Collecting logs from each microservice..."
# MODIFIED: Save Docker logs to the respective directories with the run number
docker logs hdsearch_bucket > "${BUCKET_DIR}/bucket_docker_${RUN_NUMBER}.log" 2>&1
docker logs hdsearch_midtier > "${MIDTIER_DIR}/midtier_docker_${RUN_NUMBER}.log" 2>&1
docker logs hdsearch_client > "${CLIENT_DIR}/client_docker_${RUN_NUMBER}.log" 2>&1
log "Logs saved to service-specific directories with run number $RUN_NUMBER."
echo "----------------------------------------------------" | tee -a "$MAIN_LOG_FILE"


# 6. Final Cleanup
# ----------------
log "Experiment is complete. Shutting down all services..."
docker-compose -f "$COMPOSE_FILE" down
log "All services have been stopped and removed."
log ">>> Experiment Finished <<<"
