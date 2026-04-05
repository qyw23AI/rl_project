#!/usr/bin/env bash
set -euo pipefail

# 目的：初始化 VirtualGL + TurboVNC，并保持容器前台运行。
# 安全提示：
# - 不要将 ~/.mujoco/mjkey.txt 写入镜像或仓库；请在运行时通过 volume 挂载。
# - 生产环境建议通过 SSH 隧道访问 VNC，避免直接暴露 5901 端口到公网。

VGL_CONFIG_MARKER="/var/run/.vgl_configured"
VNC_DISPLAY=":1"
VNC_GEOMETRY="1920x1080"
VNC_DEPTH="24"
VNC_LOG="/root/.vnc/$(hostname)${VNC_DISPLAY}.log"
MUJOCO_KEY="/root/.mujoco/mjkey.txt"
CHECKPOINT_DIR="/workspace/checkpoints"
LOG_DIR="/workspace/logs"

mkdir -p /var/run /root/.vnc

# 先准备持久化目录，避免训练中途因为目录不存在而报错或把数据写到临时位置。
# 默认仍保持 root 属主行为；如果你希望容器内文件按宿主用户写入，可在 docker run 时增加：
#   -u $(id -u):$(id -g)
# 同时宿主机目录也应预先 chown 给对应 UID/GID，避免权限冲突。
mkdir -p "${CHECKPOINT_DIR}" "${LOG_DIR}"
chmod 775 "${CHECKPOINT_DIR}" "${LOG_DIR}"

# 启动前检查 MuJoCo key 是否存在。缺少 key 会导致模拟器/环境初始化失败，因此在入口直接报错更容易定位。
if [[ ! -f "${MUJOCO_KEY}" ]]; then
  echo "[entrypoint][error] Missing MuJoCo key: ${MUJOCO_KEY}"
  echo "[entrypoint][hint] Please copy the key on the host first, for example:"
  echo "  scp ~/.mujoco/mjkey.txt <user>@<server>:/home/ubuntu/.mujoco/mjkey.txt"
  echo "[entrypoint][hint] Then run the container with: -v /home/ubuntu/.mujoco:/root/.mujoco:ro"
  exit 1
fi

# 首次启动时执行 vglserver_config。
# 某些版本在非交互场景会返回非零码，这里容错处理并继续启动。
if [[ ! -f "${VGL_CONFIG_MARKER}" ]]; then
  echo "[entrypoint] First run: configuring VirtualGL server..."
  if /opt/VirtualGL/bin/vglserver_config -config +s +f </dev/null; then
    echo "[entrypoint] VirtualGL configured successfully."
  else
    echo "[entrypoint] VirtualGL configuration returned non-zero (non-interactive mode). Continue with caution."
  fi
  touch "${VGL_CONFIG_MARKER}"
fi

# 若存在旧的 VNC 会话，先清理，避免端口或锁文件冲突。
if /opt/TurboVNC/bin/vncserver -list | grep -q "${VNC_DISPLAY}"; then
  echo "[entrypoint] Existing VNC session detected on ${VNC_DISPLAY}, killing it first..."
  /opt/TurboVNC/bin/vncserver -kill "${VNC_DISPLAY}" || true
fi

# 以 24-bit 色深启动 VNC，可显著降低 OpenGL/VirtualGL 显示异常概率。
echo "[entrypoint] Starting TurboVNC on ${VNC_DISPLAY} (${VNC_GEOMETRY}, depth ${VNC_DEPTH})..."
/opt/TurboVNC/bin/vncserver "${VNC_DISPLAY}" -geometry "${VNC_GEOMETRY}" -depth "${VNC_DEPTH}"

echo "[entrypoint] Ready. Inside container, use vglrun to launch GPU apps:"
echo "  vglrun conda run -n rl python train.py"
echo "  conda activate rl"
echo "  vglrun bash"

echo "[entrypoint] VNC logs: ${VNC_LOG}"
# 保持容器前台运行，便于 Docker 监管进程生命周期。
# 若日志文件暂未创建，先等待其出现。
until [[ -f "${VNC_LOG}" ]]; do
  sleep 1
done

tail -f "${VNC_LOG}"
