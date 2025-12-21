# Experiment Instructions

Step-by-step guide to run the energy proportionality experiment investigating resource disaggregation and container snapshotting.

---

## Prerequisites

### 1. System Requirements

- Ubuntu 18.04+ or compatible Linux distribution
- Root/sudo access
- At least 16GB RAM
- Multi-core CPU with C6 state support

### 2. Install Required Software

```bash
# Update package list
sudo apt-get update

# Install Podman, Podman Compose, and CRIU
sudo apt-get install -y podman podman-compose criu

# Verify installations
podman --version
podman-compose --version
criu check
```

### 4. Install Python Dependencies (for analysis)

```bash
# Python 3 should already be installed
# No external packages required - uses standard library only
python3 --version
```

---

## Step 1: Prepare the Environment

### 1.1 Navigate to Project Directory

```bash
cd /home/tsazei01/MicroSuite/energy_proportionality
```

### 1.2 Setup Disaggregated Memory Simulation

This creates a tmpfs mount that simulates CXL/disaggregated memory for storing checkpoints.

```bash
# Create 8GB memory pool for checkpoints
sudo ./scripts/setup_disaggregated_memory.sh /mnt/disaggregated_memory 8G
```

**Expected Output:**
```
=== Setting Up Disaggregated Memory Simulation ===
[INFO] Checking NUMA topology...
[INFO] Creating mount point: /mnt/disaggregated_memory
[INFO] Mounting tmpfs (size: 8G)...
[INFO] Disaggregated memory simulation ready
```

### 1.3 Set Environment Variable

```bash
export CHECKPOINT_DIR=/mnt/disaggregated_memory
```

---

## Step 2: Prepare the Dataset

Ensure the HDSearch dataset is available:

```bash
# Check if dataset exists
ls -la /home/shared_datasets/HDSearch/image_feature_vectors.dat

# If not, download it:
mkdir -p /home/shared_datasets/HDSearch
cd /home/shared_datasets/HDSearch
wget https://akshithasriraman.eecs.umich.edu/dataset/HDSearch/image_feature_vectors.dat
```

Update the dataset path in the docker-compose file if needed:

```bash
# Edit configs/docker-compose-checkpoint.yml
# Change DATASET_PATH to your actual path
```

---

## Step 3: Run the Experiment

### Option A: Automated Full Experiment (Recommended)

Run the complete experiment with baseline and multiple checkpoint cycles:

```bash
cd /home/tsazei01/MicroSuite/energy_proportionality

# Syntax: ./scripts/run_experiment.sh <name> <num_runs> <checkpoint_dir> <idle_seconds>
./scripts/run_experiment.sh energy_test 10 /mnt/disaggregated_memory 5
```

**Parameters:**
| Parameter | Description | Example |
|-----------|-------------|---------|
| `name` | Experiment name (used for results folder) | `energy_test` |
| `num_runs` | Number of checkpoint/restore cycles | `10` |
| `checkpoint_dir` | Where to store checkpoints | `/mnt/disaggregated_memory` |
| `idle_seconds` | Idle duration between checkpoint and restore | `5` |

**What happens:**
1. Baseline run (no checkpointing) - measures normal C6 residency
2. For each run (1 to N):
   - Start services
   - Generate load burst
   - Checkpoint midtier container
   - Idle period (CPU should enter C6)
   - Restore midtier container
   - Generate second load burst
   - Record metrics

### Option B: Manual Step-by-Step

If you prefer to run each step manually:

#### Start Services

```bash
cd /home/tsazei01/MicroSuite/energy_proportionality/configs

# Start all services
podman-compose -f docker-compose-checkpoint.yml up -d

# Verify services are running
podman ps
```

#### Monitor C6 State (in separate terminal)

```bash
cd /home/tsazei01/MicroSuite/energy_proportionality

# Monitor CPUs 0, 2, 4 (where services are pinned)
./scripts/monitor_c6_state.sh 0,2,4 1 c6_monitor.csv
```

#### Create Checkpoint

```bash
# Checkpoint the midtier service
./scripts/checkpoint_container.sh hdsearch_midtier /mnt/disaggregated_memory

# Note the checkpoint name printed (e.g., hdsearch_midtier_20241218_120000)
```

#### Observe Idle Period

```bash
# Wait and observe C6 residency in the monitor terminal
sleep 10
```

#### Restore Container

```bash
# Restore using the checkpoint name from earlier
./scripts/restore_container.sh hdsearch_midtier hdsearch_midtier_20241218_120000 /mnt/disaggregated_memory
```

#### Cleanup

```bash
cd /home/tsazei01/MicroSuite/energy_proportionality/configs
podman-compose -f docker-compose-checkpoint.yml down
```

---

## Step 4: Analyze Results

### 4.1 View Raw Results

```bash
# List experiment results
ls -la /home/tsazei01/MicroSuite/energy_proportionality/results/

# View the results CSV
cat results/energy_test_*/results.csv
```

### 4.2 Run Analysis Script

```bash
cd /home/tsazei01/MicroSuite/energy_proportionality

# Analyze experiment results
python3 analysis/analyze_results.py results/energy_test_*/
```

**Expected Output:**
```
============================================================
  ENERGY PROPORTIONALITY EXPERIMENT ANALYSIS
============================================================

Results Directory: results/energy_test_20241218_120000
Number of Runs: 10

------------------------------------------------------------
  CHECKPOINT/RESTORE PERFORMANCE
------------------------------------------------------------

  Checkpoint Latency:
    Average: 150.3 ms
    Min: 120.0 ms
    Max: 180.0 ms

  Restore Latency:
    Average: 85.2 ms
    Min: 70.0 ms
    Max: 100.0 ms

  Total Overhead: 235.5 ms

------------------------------------------------------------
  C6 STATE RESIDENCY
------------------------------------------------------------

  During Checkpoint Experiments:
    Average C6 Residency: 72.45%

  Baseline (No Checkpointing):
    C6 Residency: 15.30%
    Improvement: +57.15%

------------------------------------------------------------
  ENERGY ANALYSIS
------------------------------------------------------------

  Net Energy Savings: 38.50 J (61.2%)
  Break-even Idle Duration: 0.55s
```

### 4.3 Parse Turbostat Logs (Optional)

If turbostat was available during the experiment:

```bash
python3 analysis/parse_turbostat.py results/energy_test_*/run1_turbostat.log --cpus 0,2,4
```

### 4.4 Export Summary

```bash
python3 analysis/analyze_results.py results/energy_test_*/ --export summary.csv
```

---

## Step 5: Interpret Results

### Key Metrics to Evaluate

| Metric | Good Result | Meaning |
|--------|-------------|---------|
| Checkpoint Latency | < 200ms | Fast snapshot creation |
| Restore Latency | < 100ms | Quick service recovery |
| C6 Residency (checkpoint) | > 70% | CPU enters deep sleep during idle |
| C6 Improvement | > 50% | Significant improvement over baseline |
| Net Energy Savings | > 0 | Checkpointing saves energy |
| Break-even Idle | < idle_duration | Strategy is energy-positive |

### Understanding the Results

1. **If C6 residency is high during idle**: The CPU successfully entered deep sleep state when the container was checkpointed, saving power.

2. **If net energy savings is positive**: The energy saved during idle exceeds the overhead of checkpoint/restore operations.

3. **If break-even idle < your idle duration**: Your idle periods are long enough to benefit from checkpointing.

---

## Troubleshooting

### CRIU Check Fails

```bash
# Check if kernel supports checkpoint/restore
grep CONFIG_CHECKPOINT_RESTORE /boot/config-$(uname -r)

# If not enabled, you may need a different kernel
```

### Podman Checkpoint Fails

```bash
# Check Podman checkpoint support
podman container checkpoint --help

# View detailed error
podman container checkpoint --export=/tmp/test_ckpt.tar.gz hdsearch_midtier 2>&1
```

### Low C6 Residency

```bash
# Check if C6 is enabled
cat /sys/devices/system/cpu/cpu0/cpuidle/state*/name

# Check current governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# Set to powersave for better C6
echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

### Container Won't Restore

```bash
# Common cause: container was removed
# Solution: don't run 'podman-compose down' between checkpoint and restore

# Check checkpoint exists
ls -la /mnt/disaggregated_memory/
```

---

## Quick Reference

```bash
# === FULL EXPERIMENT ===
cd /home/tsazei01/MicroSuite/energy_proportionality
sudo ./scripts/setup_disaggregated_memory.sh /mnt/disaggregated_memory 8G
./scripts/run_experiment.sh my_experiment 10 /mnt/disaggregated_memory 5
python3 analysis/analyze_results.py results/my_experiment_*/

# === MANUAL CHECKPOINT/RESTORE ===
cd configs && podman-compose -f docker-compose-checkpoint.yml up -d
../scripts/checkpoint_container.sh hdsearch_midtier /mnt/disaggregated_memory
# ... wait ...
../scripts/restore_container.sh hdsearch_midtier <checkpoint_name> /mnt/disaggregated_memory
podman-compose -f docker-compose-checkpoint.yml down
```

---

## Next Steps

After completing the basic experiment:

1. **Vary idle duration**: Test with 1s, 5s, 10s, 30s idle periods
2. **Vary workload**: Adjust QPS in docker-compose to test different loads
3. **Compare services**: Checkpoint bucket vs midtier vs both
4. **Multi-node**: Extend to distributed deployment with podman-compose on each node
