# Prerequisites and Dependencies

Complete list of all requirements to run the energy proportionality experiments.

---

## System Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| Operating System | Ubuntu 18.04 LTS | Ubuntu 22.04 LTS |
| Linux Kernel | 5.15+ | 6.1+ (CXL support) |
| CPU | x86_64 with C-states | Intel Xeon (C6 support) |
| RAM | 16 GB | 32 GB+ |
| Storage | 50 GB free | 100 GB+ SSD |
| CPU Cores | 6+ cores | 8+ cores |

---

## Container Runtime (Choose One)

The experiments support **both Docker and Podman**. Podman is recommended as it has native CRIU support without requiring experimental mode.

### Runtime Comparison

| Feature | Docker | Podman |
|---------|--------|--------|
| CRIU Support | Requires experimental mode | Native support |
| Root Required | Yes (daemon) | No (rootless available) |
| Checkpoint Command | `docker checkpoint create` | `podman container checkpoint` |
| Checkpoint Format | Directory | Tar archive |

---

## Software Dependencies

### Option A: Podman (Recommended)

```bash
# Install Podman
sudo apt-get update
sudo apt-get install -y podman podman-compose

# Verify installation
podman --version          # Required: 3.4+
podman-compose --version  # Required: 1.0+

# Test checkpoint support (no extra config needed)
podman info | grep -i checkpoint
```

**Advantages of Podman:**
- Native checkpoint/restore without experimental mode
- Daemonless architecture
- Rootless container support
- Compatible with Docker images

### Option B: Docker

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add user to docker group
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt-get install -y docker-compose

# Verify installation
docker --version          # Required: 24.0+
docker-compose --version  # Required: 1.29+
```

### 2. CRIU (Checkpoint/Restore In Userspace)

```bash
# Install CRIU
sudo apt-get update
sudo apt-get install -y criu

# Verify installation
criu --version  # Required: 3.17+

# Check CRIU functionality
sudo criu check
```

### 3. Python 3

```bash
# Usually pre-installed on Ubuntu
python3 --version  # Required: 3.6+

# No external packages needed (uses standard library only)
```

### 4. System Utilities

```bash
# Install required utilities
sudo apt-get install -y \
    net-tools \
    netcat \
    numactl \
    linux-tools-common \
    linux-tools-$(uname -r)

# Verify installations
nc -h              # netcat (for health checks)
numactl --hardware # NUMA topology
turbostat --help   # CPU power monitoring (optional but recommended)
```

---

## Kernel Requirements

### Required Kernel Features

```bash
# Check kernel configuration
grep -E "CONFIG_CHECKPOINT_RESTORE|CONFIG_NAMESPACES|CONFIG_CGROUPS" /boot/config-$(uname -r)
```

**Required settings:**
```
CONFIG_CHECKPOINT_RESTORE=y
CONFIG_NAMESPACES=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
CONFIG_PID_NS=y
CONFIG_NET_NS=y
CONFIG_CGROUPS=y
CONFIG_MEMCG=y
CONFIG_CPUSETS=y
```

### CPU Idle States (C-states)

```bash
# Check available C-states
ls /sys/devices/system/cpu/cpu0/cpuidle/

# View C-state names
for state in /sys/devices/system/cpu/cpu0/cpuidle/state*/name; do
    echo "$(dirname $state | xargs basename): $(cat $state)"
done
```

**Expected output (should include C6):**
```
state0: POLL
state1: C1
state2: C1E
state3: C6
```

---

## Docker Configuration

### Enable Experimental Features

```bash
# Create or edit daemon.json
sudo tee /etc/docker/daemon.json << 'EOF'
{
    "experimental": true,
    "storage-driver": "overlay2",
    "live-restore": true
}
EOF

# Restart Docker
sudo systemctl restart docker

# Verify
docker info | grep -i experimental
# Should show: Experimental: true
```

### Required Docker Capabilities

The containers need these capabilities (configured in docker-compose):
- `SYS_PTRACE` - Process tracing for CRIU
- `SYS_ADMIN` - System administration for checkpointing
- `NET_ADMIN` - Network namespace management
- `seccomp:unconfined` - Disable seccomp for CRIU compatibility

---

## µSuite Dependencies

### Pre-built Docker Image

```bash
# Pull or verify the µSuite image exists
docker images | grep msuite-hdsearch

# If not available, build from MicroSuite repository
# (See main README.md section 5 for build instructions)
```

### Dataset

```bash
# HDSearch dataset
mkdir -p /home/shared_datasets/HDSearch
cd /home/shared_datasets/HDSearch
wget https://akshithasriraman.eecs.umich.edu/dataset/HDSearch/image_feature_vectors.dat

# Verify
ls -lh image_feature_vectors.dat
# Should be approximately 1.2 GB
```

---

## Optional Dependencies

### Turbostat (Recommended)

For detailed CPU power and C-state monitoring:

```bash
# Install linux-tools
sudo apt-get install -y linux-tools-common linux-tools-$(uname -r)

# Test turbostat
sudo turbostat --help

# If kernel version mismatch, try generic
sudo apt-get install -y linux-tools-generic
```

### Intel PCM (Optional)

For detailed Intel CPU metrics:

```bash
# Clone and build
git clone https://github.com/intel/pcm.git
cd pcm
mkdir build && cd build
cmake ..
make -j

# Run
sudo ./pcm
```

### Perf (Optional)

For performance profiling:

```bash
sudo apt-get install -y linux-perf

# Test
sudo perf stat ls
```

---

## Verification Checklist

Run this script to verify all prerequisites:

```bash
#!/bin/bash
echo "=== Prerequisites Verification ==="

# Docker
echo -n "Docker: "
docker --version 2>/dev/null && echo "OK" || echo "MISSING"

# Docker experimental
echo -n "Docker Experimental: "
docker info 2>/dev/null | grep -q "Experimental: true" && echo "OK" || echo "DISABLED"

# CRIU
echo -n "CRIU: "
criu --version 2>/dev/null && echo "OK" || echo "MISSING"

# CRIU check
echo -n "CRIU Functionality: "
sudo criu check 2>/dev/null && echo "OK" || echo "FAILED"

# Python
echo -n "Python 3: "
python3 --version 2>/dev/null && echo "OK" || echo "MISSING"

# Netcat
echo -n "Netcat: "
which nc >/dev/null 2>&1 && echo "OK" || echo "MISSING"

# Numactl
echo -n "Numactl: "
which numactl >/dev/null 2>&1 && echo "OK" || echo "MISSING"

# C6 state
echo -n "C6 State: "
ls /sys/devices/system/cpu/cpu0/cpuidle/state3 >/dev/null 2>&1 && echo "OK" || echo "NOT FOUND"

# Turbostat
echo -n "Turbostat: "
which turbostat >/dev/null 2>&1 && echo "OK" || echo "MISSING (optional)"

# Dataset
echo -n "HDSearch Dataset: "
ls /home/shared_datasets/HDSearch/image_feature_vectors.dat >/dev/null 2>&1 && echo "OK" || echo "MISSING"

# Docker image
echo -n "µSuite Docker Image: "
docker images | grep -q msuite-hdsearch && echo "OK" || echo "MISSING"

echo "=== Verification Complete ==="
```

---

## Installation Summary

### Quick Install - Podman (Recommended)

```bash
# 1. System packages with Podman
sudo apt-get update
sudo apt-get install -y \
    criu \
    podman \
    podman-compose \
    net-tools \
    netcat \
    numactl \
    python3 \
    linux-tools-common \
    linux-tools-$(uname -r)

# 2. Dataset
mkdir -p /home/shared_datasets/HDSearch
wget -P /home/shared_datasets/HDSearch \
    https://akshithasriraman.eecs.umich.edu/dataset/HDSearch/image_feature_vectors.dat

# 3. Verify
sudo criu check
podman info
```

### Quick Install - Docker (Alternative)

```bash
# 1. System packages with Docker
sudo apt-get update
sudo apt-get install -y \
    criu \
    docker.io \
    docker-compose \
    net-tools \
    netcat \
    numactl \
    python3 \
    linux-tools-common \
    linux-tools-$(uname -r)

# 2. Docker configuration (required for checkpoint support)
sudo usermod -aG docker $USER
sudo tee /etc/docker/daemon.json << 'EOF'
{
    "experimental": true,
    "storage-driver": "overlay2"
}
EOF
sudo systemctl restart docker

# 3. Dataset
mkdir -p /home/shared_datasets/HDSearch
wget -P /home/shared_datasets/HDSearch \
    https://akshithasriraman.eecs.umich.edu/dataset/HDSearch/image_feature_vectors.dat

# 4. Verify
sudo criu check
docker info | grep Experimental
```

### Force Specific Runtime

```bash
# Force Docker even if Podman is available
export CONTAINER_RUNTIME=docker

# Force Podman
export CONTAINER_RUNTIME=podman
```

---

## Troubleshooting Installation

### CRIU Check Fails

```bash
# Error: "Dirty tracking is OFF"
echo 1 | sudo tee /proc/sys/kernel/soft_dirty

# Error: "Network namespace is not available"
# Kernel needs CONFIG_NET_NS=y (usually enabled by default)
```

### Docker Checkpoint Not Working

```bash
# Ensure runc is updated
docker info | grep -i runc

# Check containerd version
containerd --version  # Should be 1.6+
```

### Turbostat Permission Denied

```bash
# Run with sudo
sudo turbostat

# Or set capabilities
sudo setcap cap_sys_rawio+ep $(which turbostat)
```

### C6 State Not Available

```bash
# Check BIOS settings - C-states must be enabled
# Check kernel parameter
cat /proc/cmdline | grep -i idle

# Remove any idle=poll or intel_idle.max_cstate limits
# Edit /etc/default/grub and remove these parameters
```

---

## Version Reference

| Component | Minimum Version | Tested Version |
|-----------|-----------------|----------------|
| Linux Kernel | 5.15 | 6.1 |
| Podman | 3.4 | 4.7 |
| Podman Compose | 1.0 | 1.0.6 |
| Docker | 24.0 | 25.0 |
| Docker Compose | 1.29 | 2.21 |
| CRIU | 3.17 | 3.18 |
| Python | 3.6 | 3.10 |
| containerd | 1.6 | 1.7 |
| runc | 1.1 | 1.1.9 |
