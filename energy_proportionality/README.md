# Energy Proportionality Research Module

Investigation of resource disaggregation and process/container snapshotting to disaggregated memory for improved energy proportionality in microservice architectures.

## Overview

This module provides tools to:
1. **Checkpoint/restore** µSuite containers using CRIU
2. **Simulate disaggregated memory** using NUMA remote memory or tmpfs
3. **Monitor C6 state** residency during idle periods
4. **Measure energy savings** from deep sleep state exploitation

## Directory Structure

```
energy_proportionality/
├── scripts/                    # Executable scripts
│   ├── checkpoint_container.sh # Checkpoint a running container
│   ├── restore_container.sh    # Restore from checkpoint
│   ├── setup_disaggregated_memory.sh  # Setup memory simulation
│   ├── monitor_c6_state.sh     # Monitor CPU C-states
│   └── run_experiment.sh       # Main experiment runner
├── configs/                    # Configuration files
│   └── docker-compose-checkpoint.yml  # Docker compose with CRIU support
├── analysis/                   # Analysis tools
│   ├── analyze_results.py      # Experiment result analyzer
│   └── parse_turbostat.py      # Turbostat log parser
├── checkpoints/                # Checkpoint storage (created at runtime)
└── results/                    # Experiment results (created at runtime)
```

## Prerequisites

### System Requirements
- Linux kernel 5.15+ (6.1+ recommended for CXL support)
- Docker 24.0+ with experimental features enabled
- CRIU 3.17+

### Installation

```bash
# Install CRIU
sudo apt-get update
sudo apt-get install -y criu

# Verify CRIU
criu check

# Enable Docker experimental features
echo '{"experimental": true}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
```

## Quick Start

### 1. Setup Disaggregated Memory Simulation

```bash
# Create tmpfs mount simulating disaggregated memory
sudo ./scripts/setup_disaggregated_memory.sh /mnt/disaggregated_memory 8G

# Export for use by other scripts
export CHECKPOINT_DIR=/mnt/disaggregated_memory
```

### 2. Run Complete Experiment

```bash
# Run full experiment (baseline + 10 checkpoint/restore cycles)
./scripts/run_experiment.sh my_experiment 10 /mnt/disaggregated_memory 5
```

### 3. Analyze Results

```bash
# Analyze experiment results
python3 analysis/analyze_results.py results/my_experiment_*/

# Parse turbostat logs
python3 analysis/parse_turbostat.py results/my_experiment_*/run1_turbostat.log
```

## Manual Operation

### Checkpoint a Container

```bash
# Start services
cd configs
docker-compose -f docker-compose-checkpoint.yml up -d

# Create checkpoint (stops container)
../scripts/checkpoint_container.sh hdsearch_midtier /mnt/disaggregated_memory

# At this point, CPU can enter C6 state
```

### Restore a Container

```bash
# Restore from checkpoint
../scripts/restore_container.sh hdsearch_midtier midtier_checkpoint_name /mnt/disaggregated_memory
```

### Monitor C6 State

```bash
# Monitor CPUs 0, 2, 4 at 1-second intervals
./scripts/monitor_c6_state.sh 0,2,4 1 c6_log.csv

# With turbostat (more detailed, requires root)
sudo turbostat --cpu 0,2,4 --interval 1 --out turbostat.log
```

## Experiment Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                    Experiment Phases                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Phase 1: Baseline                                              │
│  ├── Start all services normally                                │
│  ├── Run load generator                                         │
│  └── Measure C6 residency (baseline)                            │
│                                                                 │
│  Phase 2: Checkpoint Cycles (repeated N times)                  │
│  ├── Start services                                             │
│  ├── Load burst #1                                              │
│  ├── Checkpoint midtier → disaggregated memory                  │
│  ├── Idle period (measure C6 residency)                         │
│  ├── Restore from checkpoint                                    │
│  └── Load burst #2                                              │
│                                                                 │
│  Phase 3: Analysis                                              │
│  ├── Calculate checkpoint/restore latency                       │
│  ├── Compare C6 residency: baseline vs checkpoint               │
│  └── Estimate energy savings                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Key Metrics

| Metric | Description | Target |
|--------|-------------|--------|
| Checkpoint Latency | Time to snapshot container state | < 200ms |
| Restore Latency | Time to resume from checkpoint | < 100ms |
| C6 Residency | CPU time in deep sleep during idle | > 80% |
| Energy Savings | Net savings during idle periods | > 50% |

## Troubleshooting

### CRIU Check Fails

```bash
# Check kernel config
grep CONFIG_CHECKPOINT_RESTORE /boot/config-$(uname -r)

# Should show: CONFIG_CHECKPOINT_RESTORE=y
```

### Checkpoint Hangs

```bash
# Issue: TCP connections prevent checkpoint
# Solution: Use --tcp-established flag or close connections first
docker checkpoint create --tcp-established ...
```

### Container Won't Restore

```bash
# Check error log
cat /tmp/checkpoints/checkpoint_name/restore.log

# Common issues:
# - PID conflict: Container was recreated
# - Network: Network namespace changed
# - Mounts: Volume paths changed
```

## Research Output

After running experiments, results include:

- **results.csv**: Per-run metrics (checkpoint time, restore time, C6%)
- **\*_turbostat.log**: Detailed CPU power state data
- **\*_c6.csv**: C6 residency time series
- **summary.csv**: Aggregated statistics

## Citations

If you use this research module, please cite:

```
@inproceedings{musuite2018,
  title={μSuite: A Benchmark Suite for Microservices},
  author={Sriraman, Akshitha and Wenisch, Thomas F},
  booktitle={IEEE IISWC},
  year={2018}
}
```

## License

BSD License - See main repository LICENSE file.
