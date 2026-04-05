#!/usr/bin/env bash
set -euo pipefail

# 请先替换/导出以下占位符：
# - IMAGE: 本地构建镜像名（例如 yourrepo/rl-vgl:latest）
# - REMOTE: 远端目标镜像（例如 docker.io/yourrepo/rl-vgl:latest）
IMAGE="${IMAGE:-yourrepo/rl-vgl:latest}"
REMOTE="${REMOTE:-docker.io/yourrepo/rl-vgl:latest}"

echo "[build] Building image: ${IMAGE}"
docker build --progress=plain -t "${IMAGE}" .

echo "[test] Running quick GPU visibility check..."
# 快速验证容器内 CUDA 是否可见（在 conda rl 环境中执行）。
# 失败时立即退出，避免推送不可用镜像。
docker run --gpus all --rm "${IMAGE}" conda run -n rl python -c "import torch; print(torch.cuda.is_available())" | grep -q "True"

echo "[tag] Tagging ${IMAGE} -> ${REMOTE}"
docker tag "${IMAGE}" "${REMOTE}"

echo "[push] Pushing ${REMOTE}"
docker push "${REMOTE}"

echo "[done] Build, test and push completed successfully."

# CI 说明：
# 在 CI（如 GitHub Actions）中，应使用 Secrets 注入 registry 凭证，
# 例如 DOCKERHUB_USERNAME / DOCKERHUB_TOKEN，并在流水线中先 docker login 再执行本脚本。
