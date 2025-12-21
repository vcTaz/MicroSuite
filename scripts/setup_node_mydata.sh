#Setup podman and podman-compose
    # Install podman
    sudo apt update
    sudo apt -y install podman podman-compose
    # for saving registry login to be able to push images
    sudo apt -y install gnupg2 pass
    # change the storage folder for more space to commit the image
    podman rm -f $(podman ps -aq); podman rmi -f $(podman images -q)
	sleep 5
sudo systemctl stop podman 2>/dev/null || true
sleep 5
sudo umount /var/lib/containers 2>/dev/null || true
sudo rm -rf /var/lib/containers
sudo mkdir -p /var/lib/containers
sudo mkdir -p /mnt/newdata/dev/mkpodman
sudo mount --rbind /mnt/newdata/dev/mkpodman /var/lib/containers

#Set a podman-compose file
    mkdir microsuite
    cd microsuite
    git clone https://github.com/svassi04/MicroSuite.git
    cd MicroSuite

    # Run podman-compose example
    podman-compose up
