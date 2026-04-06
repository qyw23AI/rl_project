#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法:
  SSH_TARGET=user@server_ip [LOCAL_PROXY_HOST=127.0.0.1] [LOCAL_PROXY_PORT=7890] [REMOTE_PROXY_PORT=17890] ./proxy_forward.sh

说明:
  这个脚本应在你本机运行，用 SSH 反向转发把本机代理暴露到远端服务器。
  远端随后可以把 HTTP_PROXY/HTTPS_PROXY 指向 http://127.0.0.1:REMOTE_PROXY_PORT。

示例:
  SSH_TARGET=ubuntu@10.60.20.189 LOCAL_PROXY_PORT=7890 ./proxy_forward.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SSH_TARGET="${SSH_TARGET:-}"
LOCAL_PROXY_HOST="${LOCAL_PROXY_HOST:-127.0.0.1}"
LOCAL_PROXY_PORT="${LOCAL_PROXY_PORT:-7890}"
REMOTE_PROXY_PORT="${REMOTE_PROXY_PORT:-17890}"
SSH_OPTIONS="${SSH_OPTIONS:-}"

if [[ -z "${SSH_TARGET}" ]]; then
  echo "[error] Missing SSH_TARGET, for example: SSH_TARGET=ubuntu@10.60.20.189"
  exit 1
fi

if ! command -v ssh >/dev/null 2>&1; then
  echo "[error] Missing ssh command. Please install OpenSSH client first."
  exit 1
fi

if ! command -v nc >/dev/null 2>&1 && ! command -v netcat >/dev/null 2>&1; then
  echo "[warn] nc/netcat not found. Port availability check will be skipped."
else
  if command -v nc >/dev/null 2>&1; then
    if ! nc -z "${LOCAL_PROXY_HOST}" "${LOCAL_PROXY_PORT}" >/dev/null 2>&1; then
      echo "[error] Local proxy is not reachable at ${LOCAL_PROXY_HOST}:${LOCAL_PROXY_PORT}"
      exit 1
    fi
  fi
fi

echo "[info] Forwarding local proxy ${LOCAL_PROXY_HOST}:${LOCAL_PROXY_PORT} -> ${SSH_TARGET}:127.0.0.1:${REMOTE_PROXY_PORT}"
echo "[info] Keep this terminal open; press Ctrl+C to stop the tunnel."
echo "[info] On the server, use: export HTTP_PROXY=http://127.0.0.1:${REMOTE_PROXY_PORT}"
echo "[info] On the server, use: export HTTPS_PROXY=http://127.0.0.1:${REMOTE_PROXY_PORT}"

exec ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  ${SSH_OPTIONS} \
  -R "127.0.0.1:${REMOTE_PROXY_PORT}:${LOCAL_PROXY_HOST}:${LOCAL_PROXY_PORT}" \
  "${SSH_TARGET}"
