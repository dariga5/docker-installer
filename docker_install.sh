#!/bin/bash

ARGS="$@"
DOCKER_DEFAULT_VERSION=28.1.1
IS_FORCE=false

for ARG in $ARGS
do
    case $ARG in
        -v=*|--version=*)
            DOCKER_VERSION="${ARG#*=}"
            echo "DOWNLOAD DOCKER VERSION: ${DOCKER_VERSION}"
            shift;;
        -i=*|--install=*)
            INSTALL_SERVICE="${ARG#*=}"
            shift;;
        -f=*|--force=*)
            IS_FORCE="${ARG#*=}"
            shift;;
    esac
done

DOCKER_REPO=https://download.docker.com/linux/static/stable/x86_64

check_service() {
    if [[ $(systemctl is-active $1) == active ]]
    then
        return 1
    else
        return 0
    fi
}

restart_service() {
    SERVICE_STATE=$(check_service $1)

    if [[ $SERVICE_STATE -eq 1 ]]
    then
        sudo systemctl restart $1
    fi

}


install_docker() {

    if [[ -d /etc/docker ]]
    then
        sudo rm -rf /etc/docker
    fi

    if [[ ! -n $DOCKER_VERSION ]]
    then
        echo "DOWNLOAD DEFAULT VERSION: ${DOCKER_DEFAULT_VERSION}"
        DOCKER_VERSION=$DOCKER_DEFAULT_VERSION
    fi

    URL=$DOCKER_REPO/docker-$DOCKER_VERSION.tgz

    wget $URL -O docker-$DOCKER_VERSION.tgz

    sudo tar xzvf docker-$DOCKER_VERSION.tgz

    sudo chown -R root:root "docker"

    sudo mv docker/* /usr/bin/

    sudo mkdir /etc/docker && sudo touch /etc/docker/daemon.json
}



create_group() {
    sudo groupadd docker
    sudo usermod -aG $USER docker
}

create_services() {

    sudo bash -c 'cat << EOF > /lib/systemd/system/containerd.service

# Copyright The containerd Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
#uncomment to enable the experimental sbservice (sandboxed) version of containerd/cri integration
#Environment="ENABLE_CRI_SANDBOXES=sandboxed"
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/bin/containerd

Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
# Comment TasksMax if your systemd version does not supports it.
# Only systemd 226 and above support this version.
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target

EOF'

    sudo bash -c 'cat << EOF > /lib/systemd/system/docker.socket
[Unit]
Description=Docker Socket for the API

[Socket]
# If /var/run is not implemented as a symlink to /run, you may need to
# specify ListenStream=/var/run/docker.sock instead.
ListenStream=/run/docker.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker

[Install]
WantedBy=sockets.target

EOF'

    sudo bash -c 'cat << EOF > /lib/systemd/system/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=docker.socket network-online.target containerd.service
Requires=docker.socket
Requires=containerd.service

[Service]
Type=notify
EnvironmentFile=-/etc/sysconfig/docker
EnvironmentFile=-/etc/sysconfig/docker-storage
ExecStart=/usr/bin/dockerd \
          --containerd /run/containerd/containerd.sock \
          --exec-opt native.cgroupdriver=systemd \
          $OPTIONS \
          $DOCKER_STORAGE_OPTIONS \
          $DOCKER_NETWORK_OPTIONS
ExecReload=/bin/kill -s HUP $MAINPID
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
# kill only the docker process, not all processes in the cgroup
KillMode=process
# restart the docker process if it exits prematurely
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target

EOF'

SERVICES=(containerd.service docker.socket docker.service)

sudo systemctl daemon-reload

for SERVICE in ${SERVICES[@]}
do
    restart_service $SERVICE
done


}


DOCKER_GROUP=$(cat /etc/group | grep docker | awk -F ":" {'print $1'})

if [ -z "$DOCKER_GROUP" ]
then
    echo "Docker group not found. Was been create"
    create_group
else
    echo "Docker group already exist"
fi

DOCKER_BINARIES=$(which docker 2>/dev/null)

if [[ -z "$DOCKER_BINARIES"  ||  $IS_FORCE -eq true ]]
then
    echo "docker binaries not found. Was been installed"
    install_docker
    create_services
else
    echo "Docker already installed"
fi

if [[ -n $INSTALL_SERVICE ]]
then
    create_services
fi

DOCKER_INFO=$(docker -v)

echo "Docker has been installed: $DOCKER_INFO"
