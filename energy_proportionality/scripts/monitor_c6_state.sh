#!/bin/bash
# ==============================================================================
# C6 State Monitor
# Monitors CPU C-state residency to measure energy proportionality
# Tracks how much time CPUs spend in deep sleep states (C6)
# ==============================================================================

# Configuration
CPU_LIST="${1:-0,2,4}"
INTERVAL="${2:-1}"
OUTPUT_FILE="${3:-c6_monitor.csv}"
DURATION="${4:-0}"  # 0 = indefinite

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }

# Convert CPU list to array
IFS=',' read -ra CPUS <<< "$CPU_LIST"

# C-state paths
get_cstate_time() {
    local cpu=$1
    local state=$2
    local path="/sys/devices/system/cpu/cpu${cpu}/cpuidle/state${state}/time"
    if [ -f "$path" ]; then
        cat "$path"
    else
        echo "0"
    fi
}

get_cstate_name() {
    local cpu=$1
    local state=$2
    local path="/sys/devices/system/cpu/cpu${cpu}/cpuidle/state${state}/name"
    if [ -f "$path" ]; then
        cat "$path"
    else
        echo "unknown"
    fi
}

# Detect available C-states
detect_cstates() {
    local cpu=${CPUS[0]}
    local states=()
    for i in {0..10}; do
        if [ -d "/sys/devices/system/cpu/cpu${cpu}/cpuidle/state${i}" ]; then
            local name=$(get_cstate_name $cpu $i)
            states+=("${i}:${name}")
        fi
    done
    echo "${states[@]}"
}

log_info "C6 State Monitor Starting"
log_info "Monitoring CPUs: ${CPU_LIST}"
log_info "Interval: ${INTERVAL}s"
log_info "Output: ${OUTPUT_FILE}"

# Detect C-states
CSTATES=($(detect_cstates))
log_info "Detected C-states: ${CSTATES[*]}"

# Find C6 state index (usually state 3, but can vary)
C6_INDEX=""
for state in "${CSTATES[@]}"; do
    idx="${state%%:*}"
    name="${state##*:}"
    if [[ "$name" == *"C6"* ]] || [[ "$name" == *"POLL"* && "$idx" == "3" ]]; then
        C6_INDEX=$idx
        break
    fi
done

# Default to state 3 if C6 not found by name
if [ -z "$C6_INDEX" ]; then
    C6_INDEX=3
    log_info "C6 state not found by name, using state ${C6_INDEX}"
fi

log_info "Tracking C-state index: ${C6_INDEX}"

# Create CSV header
HEADER="timestamp,elapsed_s"
for cpu in "${CPUS[@]}"; do
    HEADER="${HEADER},cpu${cpu}_c6_us,cpu${cpu}_c6_delta_us,cpu${cpu}_c6_percent"
done
echo "$HEADER" > "$OUTPUT_FILE"

# Store initial values
declare -A PREV_C6_TIME
for cpu in "${CPUS[@]}"; do
    PREV_C6_TIME[$cpu]=$(get_cstate_time $cpu $C6_INDEX)
done

START_TIME=$(date +%s)
ITERATION=0

log_info "Monitoring started. Press Ctrl+C to stop."

while true; do
    ITERATION=$((ITERATION + 1))
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    # Check duration limit
    if [ "$DURATION" -gt 0 ] && [ "$ELAPSED" -ge "$DURATION" ]; then
        log_info "Duration limit reached. Stopping."
        break
    fi

    ROW="${TIMESTAMP},${ELAPSED}"

    # Calculate interval in microseconds
    INTERVAL_US=$((INTERVAL * 1000000))

    for cpu in "${CPUS[@]}"; do
        CURRENT_C6=$(get_cstate_time $cpu $C6_INDEX)
        DELTA=$((CURRENT_C6 - PREV_C6_TIME[$cpu]))

        # Calculate percentage (C6 time / interval time * 100)
        if [ $INTERVAL_US -gt 0 ]; then
            PERCENT=$(awk "BEGIN {printf \"%.2f\", ($DELTA / $INTERVAL_US) * 100}")
        else
            PERCENT="0.00"
        fi

        ROW="${ROW},${CURRENT_C6},${DELTA},${PERCENT}"
        PREV_C6_TIME[$cpu]=$CURRENT_C6
    done

    echo "$ROW" >> "$OUTPUT_FILE"

    # Print summary every 10 iterations
    if [ $((ITERATION % 10)) -eq 0 ]; then
        echo -ne "\r${GREEN}[${ELAPSED}s]${NC} Samples: ${ITERATION} "
    fi

    sleep "$INTERVAL"
done

log_info "Monitoring complete. Results saved to: ${OUTPUT_FILE}"

# Print summary statistics
echo ""
log_info "Summary Statistics:"
tail -n +2 "$OUTPUT_FILE" | awk -F',' '
BEGIN {
    sum = 0
    count = 0
}
{
    # Sum the percentage columns (every 3rd column starting from column 5)
    for (i = 5; i <= NF; i += 3) {
        sum += $i
        count++
    }
}
END {
    if (count > 0) {
        avg = sum / count
        printf "  Average C6 Residency: %.2f%%\n", avg
    }
}'
