#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/wazuh-user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

WAZUH_VERSION="v4.14.7"
WAZUH_DIR="/opt/wazuh-docker"
ADMIN_USER="ubuntu"

export DEBIAN_FRONTEND=noninteractive

############################################################
# Install prerequisites
############################################################

apt-get update -y

apt-get install -y \
    ca-certificates \
    curl \
    git

############################################################
# Remove potentially conflicting Docker packages
############################################################

for package in \
    docker.io \
    docker-compose \
    docker-compose-v2 \
    docker-doc \
    podman-docker \
    containerd \
    runc
do
    apt-get remove -y "$package" 2>/dev/null || true
done

############################################################
# Add Docker's official repository
############################################################

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update -y

############################################################
# Install and start Docker
############################################################

apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

systemctl enable --now docker

docker --version
docker compose version

############################################################
# Configure Wazuh kernel requirement
############################################################

cat >/etc/sysctl.d/99-wazuh.conf <<EOF
vm.max_map_count=262144
EOF

sysctl --system

############################################################
# Allow the normal EC2 user to run Docker
############################################################

if id "$ADMIN_USER" >/dev/null 2>&1; then
    usermod -aG docker "$ADMIN_USER"
fi

############################################################
# Download Wazuh Docker deployment
############################################################

if [ ! -d "$WAZUH_DIR/.git" ]; then
    git clone \
        --branch "$WAZUH_VERSION" \
        --depth 1 \
        https://github.com/wazuh/wazuh-docker.git \
        "$WAZUH_DIR"
fi

cd "$WAZUH_DIR/single-node"

############################################################
# Generate certificates and start Wazuh
############################################################

docker compose -f generate-indexer-certs.yml run --rm generator
docker compose up -d

############################################################
# Wait for the dashboard container
############################################################

DASHBOARD_CONTAINER_ID=""
DASHBOARD_RUNNING="false"

for attempt in $(seq 1 60); do
    DASHBOARD_CONTAINER_ID=$(docker compose ps -q wazuh.dashboard)

    if [ -n "$DASHBOARD_CONTAINER_ID" ]; then
        DASHBOARD_RUNNING=$(docker inspect \
            -f '{{.State.Running}}' \
            "$DASHBOARD_CONTAINER_ID")

        if [ "$DASHBOARD_RUNNING" = "true" ]; then
            echo "Wazuh dashboard container is running."
            break
        fi
    fi

    echo "Waiting for Wazuh dashboard: ${attempt}/60"
    sleep 10
done

if [ -z "$DASHBOARD_CONTAINER_ID" ] ||
   [ "$DASHBOARD_RUNNING" != "true" ]; then
    echo "Wazuh dashboard failed to start."
    docker compose ps
    docker compose logs --tail=100 wazuh.dashboard
    exit 1
fi

############################################################
# Capture host and container access information
############################################################

TOKEN=$(curl -fsS -X PUT \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
    http://169.254.169.254/latest/api/token)

PRIVATE_IP=$(curl -fsS \
    -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/local-ipv4)


CONTAINER_IP=$(docker inspect \
    -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
    "$DASHBOARD_CONTAINER_ID")

PUBLISHED_PORT=$(docker compose port wazuh.dashboard 5601 || true)

cat >/var/log/wazuh-access-info.txt <<EOF
Wazuh deployment completed.

EC2 private dashboard URL:
https://${PRIVATE_IP}

SSM port-forwarding analyst URL:
https://localhost:8443

Dashboard container IP:
${CONTAINER_IP}

Docker published port:
${PUBLISHED_PORT}
EOF

docker compose ps
cat /var/log/wazuh-access-info.txt