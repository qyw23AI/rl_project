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
CONTAINER_NAME="${CONTAINER_NAME:-rl-vgl}"
SKIP_BUILD="${SKIP_BUILD:-0}"
RECREATE_CONTAINER="${RECREATE_CONTAINER:-0}"
HOST_CHECKPOINT_DIR="${HOST_CHECKPOINT_DIR:-${HOME}/rl-data/checkpoints}"
HOST_LOG_DIR="${HOST_LOG_DIR:-${HOME}/rl-data/logs}"
MUJOCO_DIR="${HOME}/.mujoco"
MUJOCO_TAR="mujoco210-linux-x86_64.tar.gz"
MUJOCO_URL="https://mujoco.org/download/${MUJOCO_TAR}"
DOCKER_BUILDKIT_MODE="${DOCKER_BUILDKIT_MODE:-0}"
DOCKER_BUILD_PROGRESS="${DOCKER_BUILD_PROGRESS:-plain}"
QUICK_DEBUG="${QUICK_DEBUG:-0}"
PIP_USE_CN_MIRROR="${PIP_USE_CN_MIRROR:-1}"
ISAACGYMENVS_GIT_URL="${ISAACGYMENVS_GIT_URL:-https://github.com/isaac-sim/IsaacGymEnvs.git}"
ISAACGYM_GIT_URL="${ISAACGYM_GIT_URL:-}"
ISAACGYM_ARCHIVE="${ISAACGYM_ARCHIVE:-/workspace/issacgym.tar.xz}"
GIT_JOBS="${GIT_JOBS:-8}"

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
require_cmd timeout "Please install coreutils timeout command."

# if [[ -d "${REPO_DIR}/.git" ]]; then
#   echo "[sync] Repo exists. Pulling latest changes..."
#   git -C "${REPO_DIR}" pull --rebase
# else
#   echo "[sync] Repo not found. Cloning..."
#   git clone "${REPO_URL}" "${REPO_DIR}"
# fi
 
echo "[sync] Initializing/updating git submodules (if configured)..."
git -C "${REPO_DIR}" submodule sync --recursive || true
git -C "${REPO_DIR}" submodule update --init --recursive --jobs "${GIT_JOBS}" || true

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
  wget --tries=5 --waitretry=2 --timeout=30 -c -O "${MUJOCO_DIR}/${MUJOCO_TAR}" "${MUJOCO_URL}"
  tar -zxvf "${MUJOCO_DIR}/${MUJOCO_TAR}" -C "${MUJOCO_DIR}"
fi

cd "${REPO_DIR}"

echo "[preflight] Checking Docker Hub reachability (registry-1.docker.io:443)..."
if ! timeout 8 bash -lc 'cat < /dev/null > /dev/tcp/registry-1.docker.io/443' 2>/dev/null; then
  echo "[warn] Direct Docker Hub reachability check failed."
  echo "       If Docker daemon proxy is configured (e.g. Clash 127.0.0.1:7897), build can still work."
  echo "       Recommended: DOCKER_DAEMON_PROXY=http://127.0.0.1:7897 sudo -E bash ./enable_mirror_acceleration.sh"
fi

if [[ "${SKIP_BUILD}" == "1" ]]; then
  echo "[build] SKIP_BUILD=1: skip docker build, use existing image: ${IMAGE}"
  if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    echo "[error] Image not found: ${IMAGE}"
    echo "       Please build first, or run with SKIP_BUILD=0."
    exit 1
  fi
else
  echo "[build] Building Docker image: ${IMAGE}"
  if [[ "${DOCKER_BUILDKIT_MODE}" == "0" ]]; then
    echo "[build] Using legacy builder (DOCKER_BUILDKIT=0) to avoid docker/dockerfile frontend pull timeout."
    echo "[build] Tip: set DOCKER_BUILDKIT_MODE=1 to get detailed streaming logs."
    echo "[build] QUICK_DEBUG=${QUICK_DEBUG}"
    echo "[build] PIP_USE_CN_MIRROR=${PIP_USE_CN_MIRROR}"
    echo "[build] ISAACGYMENVS_GIT_URL=${ISAACGYMENVS_GIT_URL}"
    echo "[build] ISAACGYM_ARCHIVE=${ISAACGYM_ARCHIVE}"
    if [[ -n "${ISAACGYM_GIT_URL}" ]]; then
      echo "[build] ISAACGYM_GIT_URL is set"
    else
      echo "[build] ISAACGYM_GIT_URL is empty (expect local /workspace/isaacgym1 source)"
    fi
    DOCKER_BUILDKIT=0 docker build \
      --build-arg QUICK_DEBUG="${QUICK_DEBUG}" \
      --build-arg PIP_USE_CN_MIRROR="${PIP_USE_CN_MIRROR}" \
      --build-arg ISAACGYMENVS_GIT_URL="${ISAACGYMENVS_GIT_URL}" \
      --build-arg ISAACGYM_GIT_URL="${ISAACGYM_GIT_URL}" \
      --build-arg ISAACGYM_ARCHIVE="${ISAACGYM_ARCHIVE}" \
      -t "${IMAGE}" .
  else
    echo "[build] Using BuildKit (DOCKER_BUILDKIT=1, --progress=${DOCKER_BUILD_PROGRESS})."
    echo "[build] QUICK_DEBUG=${QUICK_DEBUG}"
    echo "[build] PIP_USE_CN_MIRROR=${PIP_USE_CN_MIRROR}"
    echo "[build] ISAACGYMENVS_GIT_URL=${ISAACGYMENVS_GIT_URL}"
    echo "[build] ISAACGYM_ARCHIVE=${ISAACGYM_ARCHIVE}"
    if [[ -n "${ISAACGYM_GIT_URL}" ]]; then
      echo "[build] ISAACGYM_GIT_URL is set"
    else
      echo "[build] ISAACGYM_GIT_URL is empty (expect local /workspace/isaacgym1 source)"
    fi
    DOCKER_BUILDKIT=1 docker build \
      --progress="${DOCKER_BUILD_PROGRESS}" \
      --build-arg QUICK_DEBUG="${QUICK_DEBUG}" \
      --build-arg PIP_USE_CN_MIRROR="${PIP_USE_CN_MIRROR}" \
      --build-arg ISAACGYMENVS_GIT_URL="${ISAACGYMENVS_GIT_URL}" \
      --build-arg ISAACGYM_GIT_URL="${ISAACGYM_GIT_URL}" \
      --build-arg ISAACGYM_ARCHIVE="${ISAACGYM_ARCHIVE}" \
      -t "${IMAGE}" .
  fi
fi

echo "[run] Starting container with GPU + MuJoCo mount + enlarged /dev/shm..."
# 安全提示：
# - 建议仅绑定到 127.0.0.1:5901，然后通过 SSH 隧道访问，避免公网暴露 VNC。
# - 不要把 5901 直接开放到公网防火墙。
if docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
  if [[ "${RECREATE_CONTAINER}" == "1" ]]; then
    echo "[run] RECREATE_CONTAINER=1: removing existing container ${CONTAINER_NAME}"
    docker rm -f "${CONTAINER_NAME}" >/dev/null
  else
    if [[ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}")" == "true" ]]; then
      echo "[run] Container ${CONTAINER_NAME} is already running."
      exit 0
    fi
    echo "[run] Starting existing container: ${CONTAINER_NAME}"
    docker start "${CONTAINER_NAME}" >/dev/null
    echo "[ok] Container started: ${CONTAINER_NAME}"
    exit 0
  fi
fi

docker run -d --name "${CONTAINER_NAME}" \
  --gpus all \
  --shm-size=4g \
  -e DISPLAY=:1 \
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
