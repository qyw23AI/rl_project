#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 需要替换的占位符：
# - REPO_URL: 你的 Git 仓库地址
# - REPO_DIR: 服务器上的项目目录名
# - IMAGE: 构建后的镜像名
# - HOST_CHECKPOINT_DIR: 宿主机保存 checkpoints 的目录
# - HOST_LOG_DIR: 宿主机保存 logs 的目录
REPO_URL="${REPO_URL:-git@github.com:qyw23AI/rl_project.git}"
REPO_DIR="${REPO_DIR:-${SCRIPT_DIR}}"
IMAGE="${IMAGE:-rl-vgl:latest}"
HOST_CHECKPOINT_DIR="${HOST_CHECKPOINT_DIR:-${HOME}/rl-data/checkpoints}"
HOST_LOG_DIR="${HOST_LOG_DIR:-${HOME}/rl-data/logs}"
MUJOCO_DIR="${HOME}/.mujoco"
MUJOCO_TAR="mujoco210-linux-x86_64.tar.gz"
MUJOCO_URL="https://mujoco.org/download/${MUJOCO_TAR}"

require_cmd() {
  local cmd="$1"
  local hint="$2"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "[error] Missing command: ${cmd}"
    echo "        ${hint}"
    exit 1
  fi
}

require_cmd git "Please install git first."
require_cmd wget "Please install wget first."
require_cmd tar "Please install tar first."
require_cmd docker "Please install Docker Engine and ensure 'docker' is in PATH."

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
  echo "[warn] MuJoCo key not found: ${HOME}/.mujoco/mjkey.txt"
  echo "       MuJoCo 2.1+ is typically license-free; continuing without mjkey."
  echo "       If your workflow still requires it, place the key and re-run."
fi

mkdir -p "${HOST_CHECKPOINT_DIR}" "${HOST_LOG_DIR}"

# 权限建议：如果你希望容器里写出的文件与宿主用户一致，可用 -u 显式传入 UID/GID。
# 例如：docker run -u $(id -u):$(id -g) ...
# 若目录已经由 root 创建，可在宿主机上执行 chown -R $(id -u):$(id -g) ${HOST_CHECKPOINT_DIR} ${HOST_LOG_DIR}

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
  -u "$(id -u):$(id -g)" \
  -v "${HOME}/.mujoco:/root/.mujoco:ro" \
  -v "${HOST_CHECKPOINT_DIR}:/workspace/checkpoints" \
  -v "${HOST_LOG_DIR}:/workspace/logs" \
  -p 127.0.0.1:5901:5901 \
  "${IMAGE}"

echo "[hint] Use SSH tunnel from local machine:"
echo "       ssh -N -L 5901:127.0.0.1:5901 <user>@<server_ip>"
echo "       Then connect your VNC client to: 127.0.0.1:5901"
echo "[hint] If you run into permission issues, pre-create and chown these host directories:"
echo "       mkdir -p \"${HOST_CHECKPOINT_DIR}\" \"${HOST_LOG_DIR}\""
echo "       chown -R \$(id -u):\$(id -g) \"${HOST_CHECKPOINT_DIR}\" \"${HOST_LOG_DIR}\""
echo ""
echo "[verify] After entering container, you can verify Isaac Gym install:"
echo "         conda run -n rl python -c 'import isaacgym; print(\"isaacgym ok\")'"
echo "[verify] Cartpole training example:"
echo "         conda run -n rl python ./IsaacGymEnvs/isaacgymenvs/train.py task=Cartpole"
echo "[verify] MuJoCo LD path (if needed in shell):"
echo "         export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:/root/.mujoco/mujoco210/bin"
