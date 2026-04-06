#!/usr/bin/env bash
set -euo pipefail

# 目标：尽可能提升中国大陆网络环境下的下载速度（APT / Docker / pip / conda / git）。
# 用法：
#   sudo bash ./enable_mirror_acceleration.sh
# 可选环境变量：
#   ENABLE_APT_MIRROR=1
#   ENABLE_DOCKER_MIRROR=1
#   ENABLE_PYTHON_MIRROR=1
#   ENABLE_CONDA_MIRROR=1
#   ENABLE_GIT_TUNING=1
#   DOCKER_MIRRORS=https://hub-mirror.c.163.com,https://mirror.baidubce.com

if [[ $EUID -ne 0 ]]; then
  echo "[info] Re-running with sudo..."
  exec sudo -E bash "$0" "$@"
fi

source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "[warn] This script is optimized for Ubuntu. Detected: ${ID:-unknown}"
fi

ENABLE_APT_MIRROR="${ENABLE_APT_MIRROR:-1}"
ENABLE_DOCKER_MIRROR="${ENABLE_DOCKER_MIRROR:-1}"
ENABLE_PYTHON_MIRROR="${ENABLE_PYTHON_MIRROR:-1}"
ENABLE_CONDA_MIRROR="${ENABLE_CONDA_MIRROR:-1}"
ENABLE_GIT_TUNING="${ENABLE_GIT_TUNING:-1}"
DOCKER_MIRRORS="${DOCKER_MIRRORS:-https://hub-mirror.c.163.com,https://mirror.baidubce.com}"

TARGET_USER="${SUDO_USER:-${USER:-ubuntu}}"
USER_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
TS="$(date +%Y%m%d-%H%M%S)"

echo "[step] Writing apt retry/timeouts config..."
cat >/etc/apt/apt.conf.d/99-network-acceleration <<'EOF'
Acquire::Retries "5";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
Acquire::ForceIPv4 "true";
EOF

if [[ "${ENABLE_APT_MIRROR}" == "1" && -f /etc/apt/sources.list ]]; then
  echo "[step] Configuring Ubuntu apt mirror (TUNA) with backup..."
  cp /etc/apt/sources.list "/etc/apt/sources.list.bak.${TS}"
  UBUNTU_CODENAME="${VERSION_CODENAME:-jammy}"
  cat >/etc/apt/sources.list <<EOF
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${UBUNTU_CODENAME} main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${UBUNTU_CODENAME}-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${UBUNTU_CODENAME}-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${UBUNTU_CODENAME}-security main restricted universe multiverse
EOF
fi

echo "[step] Running apt-get update with retries..."
apt-get update

if [[ "${ENABLE_DOCKER_MIRROR}" == "1" ]]; then
  echo "[step] Configuring Docker registry mirrors..."
  install -m 0755 -d /etc/docker

  # 通过 Python 合并 daemon.json，避免覆盖 nvidia-ctk 已写入的 runtime 配置。
  python3 - <<'PY'
import json, os
path = '/etc/docker/daemon.json'
cfg = {}
if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f:
        try:
            cfg = json.load(f)
        except Exception:
            cfg = {}

    raw = os.environ.get('DOCKER_MIRRORS', '').strip()
    mirrors = [m.strip() for m in raw.split(',') if m.strip()]
    if not mirrors:
      mirrors = [
        'https://hub-mirror.c.163.com',
        'https://mirror.baidubce.com'
      ]

    # 过滤已知容易返回 403 的镜像源
    bad = {
      'https://docker.m.daocloud.io',
      'https://dockerproxy.com'
    }
    mirrors = [m for m in mirrors if m not in bad]

cfg['registry-mirrors'] = mirrors
cfg.setdefault('max-concurrent-downloads', 10)
cfg.setdefault('max-concurrent-uploads', 5)

with open(path, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY

  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart docker || true
  fi
fi

if [[ "${ENABLE_PYTHON_MIRROR}" == "1" ]]; then
  echo "[step] Configuring pip mirror for user ${TARGET_USER}..."
  install -m 0755 -d "${USER_HOME}/.pip"
  cat >"${USER_HOME}/.pip/pip.conf" <<'EOF'
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn
timeout = 60
retries = 5
EOF
  chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.pip"
fi

if [[ "${ENABLE_CONDA_MIRROR}" == "1" ]]; then
  echo "[step] Configuring conda mirror for user ${TARGET_USER}..."
  cat >"${USER_HOME}/.condarc" <<'EOF'
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  nvidia: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
EOF
  chown "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.condarc"
fi

if [[ "${ENABLE_GIT_TUNING}" == "1" ]]; then
  echo "[step] Tuning git/http for unstable links (user ${TARGET_USER})..."
  sudo -u "${TARGET_USER}" git config --global http.postBuffer 524288000 || true
  sudo -u "${TARGET_USER}" git config --global http.lowSpeedLimit 1000 || true
  sudo -u "${TARGET_USER}" git config --global http.lowSpeedTime 60 || true
  sudo -u "${TARGET_USER}" git config --global core.compression 0 || true
fi

echo
echo "[done] Network acceleration settings applied."
echo "[next] You can now run: ./run_remote.sh"
echo "[hint] For best effect, also keep SSH proxy tunnel active via ./proxy_forward.sh"
