#!/bin/bash
#
# CloudGuard - Wazuh base AMI provisioner (Phase 1 / B1)
#
# Runs ONCE at Packer bake time. Produces a generic, Wazuh-ready Ubuntu 24.04
# host image: Docker Engine + Compose plugin, AWS CLI v2, the kernel setting the
# Wazuh indexer needs, and a verified AWS Systems Manager agent.
#
# This script deliberately contains NO deployment-specific state:
#   - no Wazuh manager/indexer/dashboard images
#   - no Wazuh version selection
#   - no docker-compose.yml, Wazuh config, or certificates
#   - no certificate generation
#   - no S3 artifact download, ECR authentication, or image pulls
#   - no `docker compose pull` / `docker compose up`
#   - no runtime AWS account discovery
#
# Those are runtime / B2 / B3 responsibilities and live in
# terraform/wazuh-project/scripts/install-wazuh.sh.tftpl.

set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

RUNTIME_USER="ubuntu"
APT_OPTS=(-y -o Acquire::Retries=3)
BUILD_MARKER="/var/log/cloudguard-ami-build.txt"


############################################################
# 1. Base packages required to install Docker and AWS CLI v2
############################################################

apt-get update "${APT_OPTS[@]}"
apt-get install "${APT_OPTS[@]}" \
    ca-certificates \
    curl \
    gnupg \
    unzip


############################################################
# 2. Remove any distro Docker packages that would conflict
############################################################

for pkg in \
    docker.io \
    docker-compose \
    docker-compose-v2 \
    docker-doc \
    podman-docker \
    containerd \
    runc
do
    apt-get remove -y "$pkg" || true
done


############################################################
# 3. Install Docker Engine from Docker's official Ubuntu repository
############################################################

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

ARCH="$(dpkg --print-architecture)"
UBUNTU_CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"

echo \
    "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list

apt-get update "${APT_OPTS[@]}"
apt-get install "${APT_OPTS[@]}" \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin


############################################################
# 4. Enable Docker on boot and let the runtime user use it
############################################################

systemctl enable --now docker

if id "$RUNTIME_USER" >/dev/null 2>&1; then
    usermod -aG docker "$RUNTIME_USER"
fi


############################################################
# 5. Persist the kernel setting the Wazuh indexer requires
############################################################

cat > /etc/sysctl.d/99-wazuh.conf <<'EOF'
vm.max_map_count=262144
EOF

sysctl --system


############################################################
# 6. Install AWS CLI v2 (official installer)
#
# The base image is a clean Ubuntu AMI with no AWS CLI, so this is a fresh
# install (`./aws/install`, not `--update`).
############################################################

case "$ARCH" in
    amd64) awscli_arch="x86_64" ;;
    arm64) awscli_arch="aarch64" ;;
    *) echo "ERROR: unsupported architecture '${ARCH}' for AWS CLI v2" >&2; exit 1 ;;
esac

awscli_tmp="$(mktemp -d)"
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${awscli_arch}.zip" \
    -o "${awscli_tmp}/awscliv2.zip"
unzip -q "${awscli_tmp}/awscliv2.zip" -d "${awscli_tmp}"
"${awscli_tmp}/aws/install"
rm -rf "${awscli_tmp}"


############################################################
# 7. Verify / enable the AWS Systems Manager agent
#
# Canonical's Ubuntu AWS images ship amazon-ssm-agent as a preinstalled snap,
# managed by snapd. Use the snap tooling to make sure it is started and enabled
# (AWS's documented approach for the Ubuntu snap agent); fall back to a deb
# systemd unit if that is what the image provides instead. Do NOT add a second
# SSM installation path. SSM is the only administrative route to this host
# (DECISIONS.md D-001), so a genuinely missing agent fails the build.
############################################################

if snap list amazon-ssm-agent >/dev/null 2>&1; then
    snap start --enable amazon-ssm-agent
    ssm_status="snap (amazon-ssm-agent) - $(snap services amazon-ssm-agent | awk 'NR==2 {print $2, $3}')"
elif systemctl cat amazon-ssm-agent.service >/dev/null 2>&1; then
    systemctl enable --now amazon-ssm-agent.service
    ssm_status="deb unit (amazon-ssm-agent.service)"
else
    echo "ERROR: amazon-ssm-agent is not present on the base image." >&2
    echo "SSM is the only administrative path for this host (D-001)." >&2
    echo "Add an explicit agent install step or choose a base AMI that ships it." >&2
    exit 1
fi


############################################################
# 8. Clean installation artifacts and package caches
############################################################

apt-get clean
rm -rf /var/lib/apt/lists/*


############################################################
# 9. Verify required components before the build is allowed to succeed
############################################################

docker --version
docker compose version

if ! aws_version="$(aws --version 2>&1)"; then
    echo "ERROR: 'aws --version' failed after install: ${aws_version}" >&2
    exit 1
fi
echo "$aws_version"
case "$aws_version" in
    aws-cli/2.*) : ;;
    *) echo "ERROR: expected AWS CLI major version 2, got: ${aws_version}" >&2; exit 1 ;;
esac

max_map_count="$(sysctl -n vm.max_map_count)"
if [ "$max_map_count" != "262144" ]; then
    echo "ERROR: vm.max_map_count is '${max_map_count}', expected 262144" >&2
    exit 1
fi

if ! id -nG "$RUNTIME_USER" | tr ' ' '\n' | grep -qx docker; then
    echo "ERROR: '${RUNTIME_USER}' is not in the docker group" >&2
    exit 1
fi

systemctl is-enabled docker


############################################################
# 10. Record what this image contains
############################################################

{
    echo "CloudGuard Wazuh base AMI"
    echo "built:            $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "docker:           $(docker --version)"
    echo "docker compose:   $(docker compose version)"
    echo "aws cli:          ${aws_version}"
    echo "vm.max_map_count: ${max_map_count}"
    echo "ssm agent:        ${ssm_status}"
    echo "docker group:     $(getent group docker)"
    echo
    echo "Host prerequisites only. No Wazuh application state is baked in."
} > "$BUILD_MARKER"

cat "$BUILD_MARKER"
echo "[cloudguard] base AMI provisioning complete"
