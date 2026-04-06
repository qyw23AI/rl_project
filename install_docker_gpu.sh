#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "[info] Re-running with sudo..."
  exec sudo -E bash "$0" "$@"
fi

source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "[error] This script is intended for Ubuntu only. Detected: ${ID:-unknown}"
  exit 1
fi

UBUNTU_CODENAME="${VERSION_CODENAME:-jammy}"
USERNAME="${SUDO_USER:-${USER:-ubuntu}}"
USER_HOME="$(getent passwd "${USERNAME}" | cut -d: -f6)"

echo "[step] Installing Docker prerequisites..."
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https

echo "[step] Adding Docker official repository..."
install -m 0755 -d /etc/apt/keyrings
install -m 0755 -d /etc/apt/sources.list.d
rm -f /etc/apt/keyrings/docker.gpg /etc/apt/sources.list.d/docker.list
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

echo "[step] Adding user ${USERNAME} to docker group..."
if ! getent group docker >/dev/null; then
  groupadd docker
fi
usermod -aG docker "${USERNAME}"

echo "[step] Installing NVIDIA Container Toolkit..."
install -m 0755 -d /etc/apt/keyrings
install -m 0755 -d /etc/apt/sources.list.d
rm -f /etc/apt/keyrings/nvidia-container-toolkit.gpg /etc/apt/sources.list.d/nvidia-container-toolkit.list
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor --yes -o /etc/apt/keyrings/nvidia-container-toolkit.gpg
chmod a+r /etc/apt/keyrings/nvidia-container-toolkit.gpg
distribution="$(source /etc/os-release && echo ${ID}${VERSION_ID})"
curl -fsSL "https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list" \
  | sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit.gpg] https://#g' \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update
apt-get install -y nvidia-container-toolkit

echo "[step] Configuring Docker runtime for NVIDIA..."
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

echo "[step] Validating Docker installation..."
docker --version
docker compose version

echo "[step] Validating NVIDIA runtime (requires GPU driver on host)..."
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi
else
  echo "[warn] nvidia-smi not found on host; skipping host GPU check."
fi

echo "[step] Validating container GPU access..."
docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi || true

echo
echo "[done] Docker and NVIDIA runtime setup complete."
echo "[next] Log out and back in so the docker group takes effect for ${USERNAME}."
echo "[next] Then run: ./run_remote.sh"
