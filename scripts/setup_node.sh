#Setup podman and podman-compose
    # Install podman
    sudo apt update
    sudo apt -y install podman podman-compose
    # for saving registry login to be able to push images
    sudo apt -y install gnupg2 pass
    # change the storage folder for more space to commit the image
    podman rm -f $(podman ps -aq); podman rmi -f $(podman images -q)
    sudo systemctl stop podman 2>/dev/null || true
    umount /var/lib/containers 2>/dev/null || true
    sudo rm -rf /var/lib/containers
    sudo mkdir -p /var/lib/containers
    sudo mkdir -p /dev/mkpodman
    sudo mount --rbind /dev/mkpodman /var/lib/containers

#Set a podman compose file
    mkdir microsuite
    cd microsuite
    git clone https://github.com/ucy-xilab/MicroSuite.git
    cd MicroSuite

    # Run podman compose example
    podman-compose up
