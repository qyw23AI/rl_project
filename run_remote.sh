#!/usr/bin/env bash
set -euo pipefail

# 需要替换的占位符：
# - REPO_URL: 你的 Git 仓库地址
# - REPO_DIR: 服务器上的项目目录名
# - IMAGE: 构建后的镜像名
REPO_URL="${REPO_URL:-git@github.com:YOUR_ORG/YOUR_REPO.git}"
REPO_DIR="${REPO_DIR:-rl-project}"
IMAGE="${IMAGE:-yourrepo/rl-vgl:latest}"
MUJOCO_DIR="${HOME}/.mujoco"
MUJOCO_TAR="mujoco210-linux-x86_64.tar.gz"
MUJOCO_URL="https://mujoco.org/download/${MUJOCO_TAR}"

if [[ -d "${REPO_DIR}/.git" ]]; then
  echo "[sync] Repo exists. Pulling latest changes..."
  git -C "${REPO_DIR}" pull --rebase
else
  echo "[sync] Repo not found. Cloning..."
  git clone "${REPO_URL}" "${REPO_DIR}"
fi

echo "[sync] Initializing/updating git submodules (if configured)..."
git -C "${REPO_DIR}" submodule sync --recursive || true
git -C "${REPO_DIR}" submodule update --init --recursive || true

if [[ ! -f "${HOME}/.mujoco/mjkey.txt" ]]; then
  echo "[error] Missing MuJoCo key: ${HOME}/.mujoco/mjkey.txt"
  echo "        Please place the key on server host first, then re-run."
  exit 1
fi

# 按需准备 MuJoCo 2.1.0（与常见手动流程一致）。
mkdir -p "${MUJOCO_DIR}"
if [[ ! -d "${MUJOCO_DIR}/mujoco210" ]]; then
  echo "[mujoco] Downloading MuJoCo 2.1.0 runtime..."
  wget -O "${MUJOCO_DIR}/${MUJOCO_TAR}" "${MUJOCO_URL}"
  tar -zxvf "${MUJOCO_DIR}/${MUJOCO_TAR}" -C "${MUJOCO_DIR}"
fi

cd "${REPO_DIR}"

echo "[build] Building Docker image: ${IMAGE}"
docker build -t "${IMAGE}" .

echo "[run] Starting container with GPU + MuJoCo mount + enlarged /dev/shm..."
# 安全提示：
# - 建议仅绑定到 127.0.0.1:5901，然后通过 SSH 隧道访问，避免公网暴露 VNC。
# - 不要把 5901 直接开放到公网防火墙。
docker run -d --name rl-vgl \
  --gpus all \
  --shm-size=4g \
  -v "${HOME}/.mujoco:/root/.mujoco:ro" \
  -p 127.0.0.1:5901:5901 \
  "${IMAGE}"

echo "[hint] Use SSH tunnel from local machine:"
echo "       ssh -N -L 5901:127.0.0.1:5901 <user>@<server_ip>"
echo "       Then connect your VNC client to: 127.0.0.1:5901"
echo ""
echo "[verify] After entering container, you can verify Isaac Gym install:"
echo "         conda run -n rl python -c 'import isaacgym; print(\"isaacgym ok\")'"
echo "[verify] Cartpole training example:"
echo "         conda run -n rl python ./IsaacGymEnvs/isaacgymenvs/train.py task=Cartpole"
echo "[verify] MuJoCo LD path (if needed in shell):"
echo "         export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:/root/.mujoco/mujoco210/bin"
