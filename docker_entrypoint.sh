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

mkdir -p /var/run /root/.vnc

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
