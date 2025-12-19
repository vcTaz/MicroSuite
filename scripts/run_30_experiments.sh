#!/bin/bash
# Run the experiment script 30 times and log outputs

EXPERIMENT_SCRIPT="./log_script_v2.sh"
MASTER_LOG="all_runs_master.log"

echo "Starting 30 experiment runs: $(date)" | tee "$MASTER_LOG"

for i in $(seq 1 30); do
  echo "==== Run #$i started at $(date) ====" | tee -a "$MASTER_LOG"
  
  # Run the experiment script and tee output to a run-specific log
  $EXPERIMENT_SCRIPT 2>&1 | tee "run_${i}.log"
  
  echo "==== Run #$i finished at $(date) ====" | tee -a "$MASTER_LOG"
  echo "" | tee -a "$MASTER_LOG"
  
  # Optional: small delay between runs if needed
  # sleep 5
done

echo "All 30 runs completed: $(date)" | tee -a "$MASTER_LOG"

