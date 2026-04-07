#!/usr/bin/env bash
set -euo pipefail

# 用法：
#   bash ./gpu_smoke_test.sh            # headless smoke test
#   VIEWER=1 bash ./gpu_smoke_test.sh   # 打开 viewer（需 VNC + DISPLAY=:1）

VIEWER="${VIEWER:-0}"
ITERS="${ITERS:-50}"

cd /workspace/IsaacGymEnvs

if [[ "${VIEWER}" == "1" ]]; then
  conda run -n rl python isaacgymenvs/train.py \
    task=Cartpole \
    sim_device=cuda:0 \
    rl_device=cuda:0 \
    headless=False \
    max_iterations="${ITERS}"
else
  conda run -n rl python isaacgymenvs/train.py \
    task=Cartpole \
    sim_device=cuda:0 \
    rl_device=cuda:0 \
    headless=True \
    max_iterations="${ITERS}"
fi
