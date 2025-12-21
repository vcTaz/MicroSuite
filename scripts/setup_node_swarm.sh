# All following commands should be run only on Node 0
# Note: Docker Swarm has been replaced with Podman pod-based deployment
# Close any podman-compose already running through the cloudlab profile
parallel-ssh -H "node0 node1 node2" -i "cd /microsuite/MicroSuite && podman-compose down"
# Download dataset
cd /microsuite/MicroSuite && sudo wget https://akshithasriraman.eecs.umich.edu/dataset/HDSearch/image_feature_vectors.dat

# For multi-node Podman deployment, we use podman-compose with remote connections
# Note: Podman does not have direct Swarm equivalent. For distributed deployments,
# consider using Kubernetes/k3s, or run podman-compose on each node separately.

export NODE0=$(ssh node0 hostname)
export NODE1=$(ssh node1 hostname)
export NODE2=$(ssh node2 hostname)

cd /microsuite/MicroSuite

# Deploy using podman-compose (runs on local node)
# For multi-node deployment, run this on each node with appropriate service configuration
podman-compose -f docker-compose-swarm.yml up -d
