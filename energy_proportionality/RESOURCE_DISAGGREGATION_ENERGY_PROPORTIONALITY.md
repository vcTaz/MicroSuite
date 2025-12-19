# Resource Disaggregation and Process Snapshotting for Energy Proportionality

## Executive Summary

This document investigates resource disaggregation and process/container snapshotting to disaggregated memory as mechanisms for improving energy proportionality in microservice architectures. By decoupling compute, memory, and storage resources, datacenters can achieve finer-grained power management, enabling idle resources to enter deep sleep states (e.g., C6) while maintaining rapid service restoration through memory-based checkpointing.

---

## 1. Introduction

### 1.1 Problem Statement

Modern microservice architectures suffer from poor energy proportionality—the mismatch between resource utilization and power consumption. Traditional server designs bundle compute, memory, and storage, forcing entire systems to remain powered even when workloads are sparse. This results in:

- **Idle Power Waste**: Servers at 10% utilization may consume 50% of peak power
- **Stranded Resources**: Memory remains allocated to idle processes
- **Limited Power State Exploitation**: Tightly-coupled resources prevent deep sleep states

### 1.2 Proposed Approach

We investigate two complementary strategies:

1. **Resource Disaggregation**: Physically separating compute, memory, and storage into independent pools connected via high-speed fabric
2. **Process/Container Snapshotting**: Checkpointing process state to disaggregated memory, enabling compute nodes to fully power down while preserving rapid restoration capability

---

## 2. Resource Disaggregation Architecture

### 2.1 Concept Overview

Resource disaggregation deconstructs the monolithic server model into specialized resource pools:

```
┌─────────────────────────────────────────────────────────────────┐
│                    High-Speed Fabric (CXL/RDMA)                 │
├─────────────────┬─────────────────────┬─────────────────────────┤
│   Compute Pool  │    Memory Pool      │     Storage Pool        │
│  ┌───┐ ┌───┐    │  ┌─────────────┐    │   ┌─────────────────┐   │
│  │CPU│ │CPU│    │  │ Disaggregated│   │   │ Persistent      │   │
│  └───┘ └───┘    │  │   Memory     │    │   │   Storage      │   │
│  ┌───┐ ┌───┐    │  │  (Far Memory)│    │   └─────────────────┘   │
│  │CPU│ │CPU│    │  └─────────────┘    │                         │
│  └───┘ └───┘    │                     │                         │
└─────────────────┴─────────────────────┴─────────────────────────┘
```

### 2.2 Key Technologies

| Technology | Description | Latency Profile |
|------------|-------------|-----------------|
| **CXL (Compute Express Link)** | Cache-coherent interconnect for memory pooling | ~100-300ns additional |
| **RDMA** | Remote Direct Memory Access for zero-copy data transfer | ~1-5µs |
| **NVMe-oF** | Networked storage access | ~10-100µs |
| **Gen-Z** | Memory-semantic fabric for disaggregated architectures | ~100-200ns |

### 2.3 Energy Proportionality Benefits

Resource disaggregation enables independent power management per resource pool:

- **Compute nodes** can enter deep C-states (C6/C10) when idle
- **Memory pools** can employ power-aware DRAM management
- **Storage** can spin down independently of active compute

---

## 3. Container Snapshotting to Disaggregated Memory

### 3.1 Checkpoint/Restore Mechanism

Process snapshotting leverages checkpoint/restore technology to capture complete process state:

```
┌──────────────────────────────────────────────────────────────────┐
│                    Snapshotting Workflow                         │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────┐     Checkpoint      ┌─────────────────────┐    │
│  │  Container  │ ──────────────────► │ Disaggregated Memory │    │
│  │  (Running)  │                     │   (Process Image)    │    │
│  └─────────────┘                     └─────────────────────┘    │
│        │                                       │                 │
│        ▼                                       │                 │
│  ┌─────────────┐                              │                 │
│  │ Compute Node│      Restore                 │                 │
│  │ Powers Down │ ◄────────────────────────────┘                 │
│  │    (C6)     │                                                │
│  └─────────────┘                                                │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 3.2 CRIU (Checkpoint/Restore In Userspace)

CRIU provides the foundational technology for container snapshotting:

**Captured State Includes:**
- Process memory mappings
- Open file descriptors
- Network connections (TCP state)
- Signal handlers and pending signals
- Credentials and namespaces
- cgroups configuration

**Integration with Container Runtimes:**
```
Container Runtime (containerd/runc)
         │
         ▼
    CRIU Interface
         │
    ┌────┴────┐
    ▼         ▼
Checkpoint  Restore
    │         │
    ▼         ▼
Disaggregated Memory Pool
```

### 3.3 Snapshotting to Disaggregated Memory

Traditional CRIU writes checkpoints to local storage. For optimal energy proportionality, we propose snapshotting directly to disaggregated memory:

**Advantages:**
1. **Faster Restoration**: Memory-to-memory transfer vs. storage I/O
2. **Compute Node Independence**: No local storage dependency
3. **Centralized State Management**: Memory pool can serve multiple compute nodes

**Implementation Approaches:**

| Approach | Description | Restoration Time |
|----------|-------------|------------------|
| **CXL Memory Direct** | Checkpoint directly to CXL-attached memory pool | ~10-50ms |
| **RDMA-based Snapshot** | Use RDMA for zero-copy checkpoint transfer | ~50-200ms |
| **Tiered (Memory + NVMe)** | Hot state in memory, cold state in NVMe | ~100-500ms |

---

## 4. Energy Proportionality Analysis

### 4.1 C-State Exploitation

Deep C-states provide significant power savings when compute is idle:

| C-State | Description | Exit Latency | Power Reduction |
|---------|-------------|--------------|-----------------|
| C0 | Active | N/A | 0% |
| C1 | Halt | ~1µs | ~30% |
| C3 | Sleep | ~100µs | ~60% |
| C6 | Deep Power Down | ~200-500µs | ~85% |
| C10 | Package Sleep | ~10ms | ~95% |

### 4.2 Disaggregation Impact on C6 Residency

In tightly-coupled architectures, inter-service communication often prevents deep sleep states. Disaggregation enables:

```
Traditional Architecture:
┌─────────────────────────────────────────┐
│ Server (Monolithic)                     │
│  [CPU]◄────────►[Memory]◄──────►[Storage]│
│    │              ▲                     │
│    └──────────────┘                     │
│  (Memory access prevents C6)            │
└─────────────────────────────────────────┘

Disaggregated Architecture:
┌─────────────────┐    ┌─────────────────┐
│  Compute Node   │    │  Memory Pool    │
│   [CPU]         │◄──►│  (Always On)    │
│   (Can enter    │    │                 │
│    C6/C10)      │    │                 │
└─────────────────┘    └─────────────────┘
```

### 4.3 Microservice Workload Characteristics

Based on µSuite benchmark analysis, microservices exhibit:

- **Bursty Request Patterns**: Significant idle periods between request bursts
- **Variable Processing Time**: 1ms - 100ms per request
- **Inter-Service Latency Tolerance**: Many services tolerate 10-100ms delays

These characteristics make microservices ideal candidates for snapshot-based power management.

---

## 5. Implementation Framework

### 5.1 System Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                      Orchestration Layer                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │
│  │   Scheduler  │  │  Power Mgr   │  │  Snapshot Controller     │  │
│  └──────────────┘  └──────────────┘  └──────────────────────────┘  │
├────────────────────────────────────────────────────────────────────┤
│                       Container Runtime                            │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  containerd + CRIU Integration                               │  │
│  └──────────────────────────────────────────────────────────────┘  │
├────────────────────────────────────────────────────────────────────┤
│                        Hardware Layer                              │
│  ┌─────────────┐  ┌──────────────────────┐  ┌─────────────────┐   │
│  │Compute Nodes│  │CXL Memory Expanders  │  │ NVMe Storage    │   │
│  │(Intel Xeon) │  │(Samsung/SK Hynix)    │  │    Pool         │   │
│  └─────────────┘  └──────────────────────┘  └─────────────────┘   │
└────────────────────────────────────────────────────────────────────┘
```

### 5.2 Snapshotting Workflow

```python
# Pseudocode for energy-aware snapshot management

class SnapshotController:
    def on_idle_detected(self, container_id, idle_duration):
        if idle_duration > SNAPSHOT_THRESHOLD:
            # Checkpoint to disaggregated memory
            snapshot = criu.checkpoint(
                container_id,
                target=disaggregated_memory_pool,
                method='cxl_direct'
            )

            # Transition compute node to deep sleep
            compute_node.enter_c_state('C6')

            # Register for wake-on-request
            load_balancer.register_wake_handler(
                container_id,
                callback=self.restore_container
            )

    def restore_container(self, container_id, request):
        # Wake compute node
        compute_node.exit_c_state()

        # Restore from disaggregated memory
        criu.restore(
            container_id,
            source=disaggregated_memory_pool
        )

        # Forward queued request
        container.handle_request(request)
```

### 5.3 Decision Criteria for Snapshotting

| Factor | Threshold | Action |
|--------|-----------|--------|
| Idle Duration | > 500ms | Consider snapshot |
| Request Arrival Rate | < 10 req/s | Snapshot eligible |
| Memory Footprint | < 1GB | Fast snapshot |
| Restoration SLA | < 100ms | Use memory snapshot |
| Restoration SLA | < 1s | Use tiered snapshot |

---

## 6. Integration with µSuite Benchmarks

### 6.1 Current Infrastructure

The µSuite benchmark suite provides the experimental foundation:

**Disaggregated Container Deployment:**
- Separate containers for bucket, midtier, and client tiers
- CPU pinning via `cpuset` for isolation
- Per-service power monitoring via turbostat

**C6 State Monitoring:**
- Single-node variants track C6 residency via sysfs
- Measurement of idle state transitions during inter-service communication

### 6.2 Proposed Extensions

To fully evaluate snapshotting to disaggregated memory:

1. **CRIU Integration**
   - Enable checkpoint/restore for µSuite containers
   - Measure snapshot creation and restoration latency

2. **Simulated Disaggregated Memory**
   - Use NUMA remote memory as proxy for CXL memory
   - Measure memory access latency impact

3. **Energy Measurement**
   - Extend turbostat monitoring to include package power
   - Correlate C-state residency with actual power savings

4. **Workload-Aware Snapshotting**
   - Implement idle detection in load generators
   - Trigger snapshots during detected idle periods

---

## 7. Expected Outcomes

### 7.1 Energy Savings Projection

| Scenario | Power Reduction | Notes |
|----------|-----------------|-------|
| Monolithic (baseline) | 0% | Always-on servers |
| Container disaggregation only | 15-25% | Limited C-state exploitation |
| + Aggressive C6 | 35-50% | Idle periods in C6 |
| + Snapshotting to disaggregated memory | 60-75% | Full power-down during idle |

### 7.2 Latency Impact

| Operation | Expected Latency |
|-----------|------------------|
| Snapshot creation (1GB container) | 50-200ms |
| Restore from CXL memory | 20-100ms |
| Restore from RDMA memory | 100-300ms |
| Total cold-start penalty | 100-500ms |

---

## 8. Challenges and Mitigations

### 8.1 Technical Challenges

| Challenge | Mitigation Strategy |
|-----------|---------------------|
| Checkpoint size for large memory footprints | Incremental checkpointing, compression |
| Network connection state | TCP connection migration, proxy-based reconnection |
| Latency-sensitive workloads | Tiered approach: keep hot services active |
| Memory pool availability | Redundant memory pools, spill to NVMe |

### 8.2 Research Questions

1. What is the optimal idle threshold for triggering snapshots?
2. How does checkpoint/restore latency scale with container memory footprint?
3. What is the break-even point where snapshotting energy savings exceed overhead?
4. How can predictive models anticipate request arrivals to pre-warm containers?

---

## 9. Conclusion

Resource disaggregation combined with process snapshotting to disaggregated memory presents a compelling approach for improving datacenter energy proportionality. By enabling compute nodes to enter deep power-saving states while maintaining rapid service restoration capability, this architecture addresses the fundamental mismatch between server power consumption and actual utilization.

The µSuite benchmark infrastructure provides a solid foundation for experimental validation. Extending this platform with CRIU integration and simulated disaggregated memory will enable quantitative assessment of the energy proportionality benefits.

---

## References

1. Lim, K., et al. "Disaggregated Memory for Expansion and Sharing in Blade Servers." ISCA 2009.
2. Aguilera, M., et al. "Remote Memory in the Age of Fast Networks." SoCC 2017.
3. CXL Consortium. "Compute Express Link Specification." 2022.
4. CRIU Project. "Checkpoint/Restore In Userspace." https://criu.org/
5. Sriraman, A. and Wenisch, T. "µSuite: A Benchmark Suite for Microservices." IISWC 2018.
6. Lo, D., et al. "Heracles: Improving Resource Efficiency at Scale." ISCA 2015.
7. Kanev, S., et al. "Profiling a Warehouse-Scale Computer." ISCA 2015.

---

## Appendix A: Experimental Configuration

### A.1 Hardware Requirements

- **Compute**: Intel Xeon Scalable (4th Gen+) with CXL 2.0 support
- **Memory Expander**: CXL Type-3 memory device (Samsung CMM-D, SK Hynix CMS)
- **Network**: 100GbE or InfiniBand for RDMA-based approaches
- **Storage**: NVMe-oF capable storage pool

### A.2 Software Stack

- **OS**: Linux 6.1+ (CXL subsystem support)
- **Container Runtime**: containerd 1.7+ with CRIU 3.18+
- **Orchestration**: Kubernetes with custom scheduler extensions
- **Monitoring**: turbostat, perf, Intel PCM

---

*Document Version: 1.0*
*Last Updated: December 2024*
