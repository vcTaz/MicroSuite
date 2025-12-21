
       Automation Script
#
# This script automates the process of running the HDSearch microservices,
# monitoring them with turbostat, and collecting logs.
#
# What it does:
# 1. Defines file names for podman-compose and logs.
# 2. Cleans up any previous Podman containers and old logs.
# 3. Starts turbostat in the background to capture CPU idleness data.
# 4. Starts each microservice sequentially, logging timestamps for each event.
# 5. Waits for the client's load generation to complete.
# 6. Stops the turbostat process.
# 7. Saves the individual logs for each microservice.
# 8. Stops and removes all Podman containers.
# ==============================================================================

# --- Configuration ---
# The name of your Podman Compose file.
COMPOSE_FILE="docker-compose-hdsearch-split.yml"

# Log file for the main experiment script's output.
MAIN_LOG_FILE="experiment_run.log"

# Log file for turbostat output.
TURBOSTAT_LOG_FILE="turbostat_output.log"

# --- Helper function for logging with timestamps ---
log() {
      # This function prints a message to both the console and the main log file.
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$MAIN_LOG_FILE"
}

# --- Main Script ---

# 1. Initial Cleanup
# -------------------
# Clear the main log file for a fresh run.
> "$MAIN_LOG_FILE"

log ">>> Starting Experiment <<<"
log "Performing initial cleanup..."
# Shut down any containers defined in the compose file, if they are running.
podman-compose -f "$COMPOSE_FILE" down
# Remove old log files to prevent confusion.
rm -f "$TURBOSTAT_LOG_FILE" bucket.log midtier.log client.log
log "Cleanup complete."
echo "----------------------------------------------------" | tee -a "$MAIN_LOG_FILE"


# 2. Start Turbostat Monitoring
# -----------------------------
log "Starting turbostat to monitor CPU idleness..."
# The '--out' flag directs output to a file.
# We run it with sudo and in the background (&).
# We capture its Process ID (PID) so we can stop it later.
sudo turbostat --interval 5 --out "$TURBOSTAT_LOG_FILE" &
TURBOSTAT_PID=$!
# Check if turbostat started successfully.
if ! ps -p $TURBOSTAT_PID > /dev/null; then
      log "ERROR: Failed to start turbostat. Do you have permissions?"
        exit 1
        fi
        log "Turbostat is running in the background with PID: $TURBOSTAT_PID"
        echo "----------------------------------------------------" | tee -a "$MAIN_LOG_FILE"


# 3. Launch Microservices Sequentially
# ------------------------------------
log "Launching 'bucket' service..."
podman-compose -f "$COMPOSE_FILE" up -d bucket
log "'bucket' service started."
sleep 5 # Give it a moment to initialize.

log "Launching 'midtier' service..."
podman-compose -f "$COMPOSE_FILE" up -d midtier
log "'midtier' service started."
sleep 5 # Give it a moment to initialize.

log "Launching 'client' service to generate load..."
podman-compose -f "$COMPOSE_FILE" up -d client
log "'client' service started. Now waiting for it to finish."
echo "----------------------------------------------------" | tee -a "$MAIN_LOG_FILE"


# 4. Wait for Client to Finish
# ----------------------------
# We monitor the logs of the client container in the background.
# The `grep -m 1` command will exit successfully once it finds the target string.
# The `wait` command pauses the script until the backgrounded `podman logs` command exits.
podman logs -f hdsearch_client | grep -m 1 "Load generator finished" &
wait $!
log "Client has finished its load generation task."
echo "----------------------------------------------------" | tee -a "$MAIN_LOG_FILE"


# 5. Stop Turbostat and Collect Logs
# ----------------------------------
log "Stopping turbostat (PID: $TURBOSTAT_PID)..."
# Use the stored PID to stop the background turbostat process.
sudo kill $TURBOSTAT_PID
# Wait a moment to ensure it has terminated cleanly.
wait $TURBOSTAT_PID 2>/dev/null
log "Turbostat stopped."

log "Collecting logs from each microservice..."
podman logs hdsearch_bucket > bucket.log 2>&1
podman logs hdsearch_midtier > midtier.log 2>&1
podman logs hdsearch_client > client.log 2>&1
log "Logs saved to bucket.log, midtier.log, and client.log."
echo "----------------------------------------------------" | tee -a "$MAIN_LOG_FILE"


# 6. Final Cleanup
# ----------------
log "Experiment is complete. Shutting down all services..."
podman-compose -f "$COMPOSE_FILE" down
log "All services have been stopped and removed."
log ">>> Experiment Finished <<<"


