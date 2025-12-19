# Implementation Guide: Snapshotting to Disaggregated Memory

## Overview

This guide provides practical implementation details for extending the µSuite benchmark infrastructure to support container snapshotting to disaggregated memory for improved energy proportionality.

---

## 1. Prerequisites

### 1.1 System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| Linux Kernel | 5.15+ | 6.1+ (CXL support) |
| CRIU | 3.17+ | 3.18+ |
| containerd | 1.6+ | 1.7+ |
| Docker | 24.0+ | 25.0+ |
| Memory | 32GB | 64GB+ |

### 1.2 Installation

```bash
# Install CRIU
sudo apt-get update
sudo apt-get install -y criu

# Verify installation
criu check

# Install additional dependencies
sudo apt-get install -y \
    libprotobuf-dev \
    protobuf-compiler \
    libcap-dev \
    libnl-3-dev \
    libnet1-dev
```

---

## 2. Enabling Container Checkpointing

### 2.1 Docker Configuration

Configure Docker daemon for experimental checkpoint support:

```json
// /etc/docker/daemon.json
{
  "experimental": true,
  "storage-driver": "overlay2",
  "live-restore": true
}
```

```bash
# Restart Docker
sudo systemctl restart docker
```

### 2.2 containerd Configuration

```toml
# /etc/containerd/config.toml
version = 2

[plugins."io.containerd.grpc.v1.cri"]
  [plugins."io.containerd.grpc.v1.cri".containerd]
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
        SystemdCgroup = true

[plugins."io.containerd.runtime.v1.linux"]
  criu_path = "/usr/sbin/criu"
```

---

## 3. µSuite Integration

### 3.1 Modified Docker Compose for Checkpoint Support

```yaml
# docker-compose-hdsearch-checkpoint.yml
version: "3.8"

services:
  bucket:
    image: msuite-hdsearch-fixed
    container_name: hdsearch_bucket
    ports:
      - "50050:50050"
    volumes:
      - /home/shared_datasets/HDSearch:/home
      - /var/lib/checkpoint:/checkpoint  # Checkpoint storage
    stdin_open: true
    tty: true
    privileged: true
    cpuset: '0'
    security_opt:
      - seccomp:unconfined  # Required for CRIU
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
    command: >
      bash -c "
        cd /MicroSuite/src/HDSearch/bucket_service/service &&
        ./bucket_server /home/image_feature_vectors.dat 0.0.0.0:50050 2 1 0 1
      "

  midtier:
    image: msuite-hdsearch-fixed
    container_name: hdsearch_midtier
    ports:
      - "50054:50054"
    volumes:
      - /home/shared_datasets/HDSearch:/home
      - /var/lib/checkpoint:/checkpoint
    stdin_open: true
    tty: true
    privileged: true
    cpuset: '2'
    security_opt:
      - seccomp:unconfined
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
    depends_on:
      - bucket
    command: >
      bash -c "
        while ! nc -z bucket 50050; do sleep 1; done &&
        cd /MicroSuite/src/HDSearch/mid_tier_service/service &&
        echo 'bucket:50050' > bucket_servers_IP.txt &&
        ./mid_tier_server 1 13 1 1 bucket_servers_IP.txt /home/image_feature_vectors.dat 2 0.0.0.0:50054 1 1 1 0
      "
```

### 3.2 Checkpoint Script

```bash
#!/bin/bash
# checkpoint_container.sh - Checkpoint a µSuite container

CONTAINER_NAME="$1"
CHECKPOINT_DIR="/var/lib/checkpoint"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CHECKPOINT_NAME="${CONTAINER_NAME}_${TIMESTAMP}"

# Create checkpoint directory
mkdir -p "${CHECKPOINT_DIR}/${CHECKPOINT_NAME}"

echo "Creating checkpoint for ${CONTAINER_NAME}..."

# Checkpoint the container
docker checkpoint create \
    --checkpoint-dir="${CHECKPOINT_DIR}" \
    --leave-running=false \
    "${CONTAINER_NAME}" \
    "${CHECKPOINT_NAME}"

if [ $? -eq 0 ]; then
    echo "Checkpoint created: ${CHECKPOINT_DIR}/${CHECKPOINT_NAME}"

    # Record checkpoint size
    CHECKPOINT_SIZE=$(du -sh "${CHECKPOINT_DIR}/${CHECKPOINT_NAME}" | cut -f1)
    echo "Checkpoint size: ${CHECKPOINT_SIZE}"

    # Trigger C-state transition
    echo "Container stopped. CPU can enter deep C-state."
else
    echo "Checkpoint failed!"
    exit 1
fi
```

### 3.3 Restore Script

```bash
#!/bin/bash
# restore_container.sh - Restore a µSuite container from checkpoint

CONTAINER_NAME="$1"
CHECKPOINT_NAME="$2"
CHECKPOINT_DIR="/var/lib/checkpoint"

echo "Restoring ${CONTAINER_NAME} from ${CHECKPOINT_NAME}..."

START_TIME=$(date +%s%N)

docker start \
    --checkpoint="${CHECKPOINT_NAME}" \
    --checkpoint-dir="${CHECKPOINT_DIR}" \
    "${CONTAINER_NAME}"

END_TIME=$(date +%s%N)
RESTORE_TIME=$(( (END_TIME - START_TIME) / 1000000 ))

if [ $? -eq 0 ]; then
    echo "Container restored in ${RESTORE_TIME}ms"
else
    echo "Restore failed!"
    exit 1
fi
```

---

## 4. Simulating Disaggregated Memory

### 4.1 Using NUMA Remote Memory

For systems without CXL hardware, use NUMA remote memory as a proxy:

```bash
# Check NUMA topology
numactl --hardware

# Allocate checkpoint storage on remote NUMA node
mkdir -p /mnt/disaggregated_mem
mount -t tmpfs -o size=16G,mpol=bind:1 tmpfs /mnt/disaggregated_mem
```

### 4.2 Memory-Backed Checkpoint Storage

```bash
#!/bin/bash
# setup_disaggregated_checkpoint.sh

# Create tmpfs mount for checkpoint storage (simulates disaggregated memory)
CHECKPOINT_MOUNT="/mnt/checkpoint_pool"
CHECKPOINT_SIZE="8G"

# Create mount point
sudo mkdir -p ${CHECKPOINT_MOUNT}

# Mount tmpfs on remote NUMA node (node 1)
sudo mount -t tmpfs \
    -o size=${CHECKPOINT_SIZE},mpol=bind:1 \
    tmpfs ${CHECKPOINT_MOUNT}

# Set permissions
sudo chmod 777 ${CHECKPOINT_MOUNT}

echo "Disaggregated memory checkpoint pool ready at ${CHECKPOINT_MOUNT}"
```

---

## 5. Energy-Aware Experiment Automation

### 5.1 Enhanced Experiment Script

```bash
#!/bin/bash
# run_checkpoint_experiment.sh

COMPOSE_FILE="docker-compose-hdsearch-checkpoint.yml"
CHECKPOINT_DIR="/mnt/checkpoint_pool"
RESULTS_DIR="checkpoint_experiment_results"
IDLE_THRESHOLD_MS=500

mkdir -p ${RESULTS_DIR}

# Start services
docker-compose -f ${COMPOSE_FILE} up -d

# Wait for services to initialize
sleep 10

# Run load generator with checkpoint triggers
run_with_checkpointing() {
    local RUN_NUM=$1

    echo "=== Run ${RUN_NUM} ==="

    # Start turbostat monitoring
    sudo turbostat --cpu 0,2,4 --interval 1 \
        --out "${RESULTS_DIR}/turbostat_run${RUN_NUM}.log" &
    TURBO_PID=$!

    # Generate load (configurable duration)
    docker exec hdsearch_client bash -c "
        cd /MicroSuite/src/HDSearch/load_generator &&
        ./load_generator_open_loop /home/image_feature_vectors.dat \
            ./results/ 1 30 100 midtier:50054 dummy1 dummy2 dummy3
    "

    # Simulate idle period
    echo "Idle period - creating checkpoint..."
    CHECKPOINT_START=$(date +%s%N)

    docker checkpoint create \
        --checkpoint-dir=${CHECKPOINT_DIR} \
        hdsearch_midtier \
        "midtier_run${RUN_NUM}"

    CHECKPOINT_END=$(date +%s%N)
    CHECKPOINT_TIME=$(( (CHECKPOINT_END - CHECKPOINT_START) / 1000000 ))
    echo "Checkpoint time: ${CHECKPOINT_TIME}ms"

    # Measure C6 residency during idle
    sleep 5  # Simulated idle period

    # Restore for next burst
    RESTORE_START=$(date +%s%N)

    docker start \
        --checkpoint="midtier_run${RUN_NUM}" \
        --checkpoint-dir=${CHECKPOINT_DIR} \
        hdsearch_midtier

    RESTORE_END=$(date +%s%N)
    RESTORE_TIME=$(( (RESTORE_END - RESTORE_START) / 1000000 ))
    echo "Restore time: ${RESTORE_TIME}ms"

    # Stop turbostat
    sudo kill ${TURBO_PID}

    # Record results
    echo "${RUN_NUM},${CHECKPOINT_TIME},${RESTORE_TIME}" >> \
        "${RESULTS_DIR}/timing_results.csv"
}

# Initialize results file
echo "run,checkpoint_ms,restore_ms" > "${RESULTS_DIR}/timing_results.csv"

# Run multiple experiments
for i in $(seq 1 10); do
    run_with_checkpointing $i
done

# Cleanup
docker-compose -f ${COMPOSE_FILE} down

echo "Experiment complete. Results in ${RESULTS_DIR}/"
```

### 5.2 C6 State Analysis Script

```bash
#!/bin/bash
# analyze_c6_residency.sh

TURBOSTAT_LOG="$1"

if [ -z "$TURBOSTAT_LOG" ]; then
    echo "Usage: $0 <turbostat_log_file>"
    exit 1
fi

echo "=== C6 State Analysis ==="

# Extract C6 residency percentages
grep -E "^[0-9]" ${TURBOSTAT_LOG} | \
    awk '{
        count++;
        c6_sum += $9;  # Adjust column based on turbostat version
    }
    END {
        print "Samples: " count;
        print "Average C6 Residency: " c6_sum/count "%";
    }'

# Calculate power savings potential
# C6 provides approximately 85% power reduction when active
```

---

## 6. Metrics Collection

### 6.1 Key Metrics

| Metric | Source | Unit |
|--------|--------|------|
| Checkpoint Creation Time | Script timing | ms |
| Checkpoint Size | du command | MB |
| Restore Time | Script timing | ms |
| C6 Residency | turbostat | % |
| Package Power | turbostat | Watts |
| Request Latency | µSuite results | µs |

### 6.2 Results Aggregation

```python
#!/usr/bin/env python3
# aggregate_results.py

import pandas as pd
import sys

def analyze_experiment(results_dir):
    # Load timing results
    timing = pd.read_csv(f"{results_dir}/timing_results.csv")

    print("=== Checkpoint/Restore Performance ===")
    print(f"Mean Checkpoint Time: {timing['checkpoint_ms'].mean():.1f}ms")
    print(f"Mean Restore Time: {timing['restore_ms'].mean():.1f}ms")
    print(f"Total Overhead: {(timing['checkpoint_ms'] + timing['restore_ms']).mean():.1f}ms")

    # Estimate energy savings
    # Assumptions: 100W server, C6 provides 85% reduction
    idle_time_s = 5  # Simulated idle period
    power_saved_per_idle = 100 * 0.85 * idle_time_s  # Watt-seconds

    overhead_energy = 100 * (timing['checkpoint_ms'].mean() +
                              timing['restore_ms'].mean()) / 1000

    net_savings = power_saved_per_idle - overhead_energy

    print(f"\n=== Energy Analysis ===")
    print(f"Energy Saved During Idle: {power_saved_per_idle:.1f} J")
    print(f"Checkpoint/Restore Overhead: {overhead_energy:.1f} J")
    print(f"Net Energy Savings: {net_savings:.1f} J")

if __name__ == "__main__":
    analyze_experiment(sys.argv[1] if len(sys.argv) > 1 else ".")
```

---

## 7. Troubleshooting

### 7.1 Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| CRIU check fails | Missing kernel features | Enable CONFIG_CHECKPOINT_RESTORE |
| Checkpoint hangs | TCP connections | Use --tcp-established flag |
| Restore fails | PID namespace conflict | Use fresh container name |
| Memory errors | Insufficient checkpoint space | Increase tmpfs size |

### 7.2 Debugging Commands

```bash
# Verify CRIU capabilities
criu check --all

# Test checkpoint without container runtime
criu dump -t <PID> -D /tmp/checkpoint --shell-job

# Check Docker checkpoint support
docker info | grep -i checkpoint

# Monitor checkpoint directory
watch -n 1 'ls -lah /mnt/checkpoint_pool'
```

---

## 8. Next Steps

1. **Baseline Measurements**: Run µSuite without checkpointing to establish baseline power consumption
2. **Checkpoint Overhead**: Measure checkpoint/restore latency for different container sizes
3. **C6 Correlation**: Correlate checkpoint-induced idle periods with C6 residency
4. **Workload Tuning**: Optimize idle threshold for different workload patterns
5. **CXL Evaluation**: Test with actual CXL memory hardware when available

---

*Implementation Guide Version: 1.0*
*Last Updated: December 2024*
