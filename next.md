# Next Steps：在 RTX 4090服务器上使用docker真正跑通 GPU 强化学习

## A. 目标

- 将当前“CPU 可验证”状态升级为“RTX 4090 可稳定 GPU 训练 + 可视化”。

## B. 必做改造项（按优先级）

### 1) 升级 PyTorch/CUDA 栈以支持 `sm_89`

- 现状：当前环境使用旧 Torch（不支持 4090）。
- 目标：切换到支持 Ada 架构（4090）的 Torch 版本（建议 Torch 2.4+，CUDA 12.1/12.4 轮子）。
- 验收：
  - `python -c "import torch; print(torch.cuda.get_device_name(0))"` 正常；
  - 不再出现 `no kernel image is available`。

### 2) 处理 Isaac Gym 与新 Torch 的兼容性

- 现状：`isaacgym 1.0rc4` 为老二进制分发，和新 Torch 栈存在不确定兼容风险。
- 目标：
  - 优先验证现有 `isaacgym` + 新 Torch 是否可跑最小任务；
  - 若不兼容，准备迁移到 NVIDIA 新一代仿真栈（Isaac Sim / Isaac Lab）。
- 验收：`task=Cartpole` 在 `sim_device=cuda:0 rl_device=cuda:0` 下可启动并迭代。

### 3) 固化依赖，避免运行时重解析

- 现状：editable 安装易引发二次依赖解析和版本漂移。
- 目标：
  - requirements 锁定关键版本（torch/torchvision/rl-games/hydra 等）；
  - 源码包安装统一使用 `--no-deps`；
  - 输出一份可复现的版本清单（`pip freeze`）。
- 验收：重建镜像后版本一致，训练行为一致。

### 4) 统一容器启动路径（VNC/entrypoint）

- 现状：历史上存在绕过 entrypoint 导致 VNC 不可用的问题。
- 目标：
  - 固化唯一启动命令（run_remote.sh）；
  - VNC 使用固定 `DISPLAY=:1`；
  - 保证 viewer 可见。
- 验收：任意一次重启后都能通过 SSH 隧道 + VNC 进入桌面并看到训练窗口。

## C. 推荐执行顺序

1. 新建 `rl-gpu4090` 分支或新镜像 tag（避免污染当前可用 CPU 环境）。
2. 升级 Torch/CUDA 并完成最小 CUDA 自检。
3. 验证 `isaacgym` 最小任务（先 headless，再 viewer）。
4. 跑 Cartpole GPU smoke test（10~50 iter）。
5. 固化依赖与启动脚本，回归测试 VNC 可视化。

## D. 当前已完成（基线）

- CPU 训练已跑通并保存 checkpoint。
- VNC 会话可用，可用于实时观察。
- 问题归档见 [issues.md](issues.md)。

## E. 镜像可拉取性结论（本次核验）

- 结论：`nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04` 在 Docker Hub 上存在，可拉取。
- 依据：Docker Hub tags 页面可检索到该 tag，且页面给出了标准拉取命令与镜像层信息。
- 参考：<https://hub.docker.com/r/nvidia/cuda/tags?page=1&name=12.1.1-cudnn8-runtime-ubuntu22.04>

## F. 重建后端到端验证流程（IsaacGym + MuJoCo + 本机可视化）

### 0) 前置条件（服务器）

- 已安装 Docker 与 NVIDIA Container Toolkit。
- 项目目录位于服务器，例如 `/home/ubuntu/rl_project`。
- MuJoCo 2.1.0 已在宿主机准备好：`~/.mujoco/mujoco210`。
- 使用本文档中的统一入口脚本启动容器，避免绕过 entrypoint。

### 1) 重建镜像

在项目根目录执行：

- `docker build -t rl-vgl:latest .`

说明：

- 构建会安装锁定依赖；
- `isaacgym` 与 `IsaacGymEnvs` 以 `--no-deps` 方式安装；
- 构建末尾会产出 `/workspace/requirements.freeze.txt`（容器内路径）。

### 2) 启动容器（固定 DISPLAY=:1 + VNC）

推荐直接使用统一脚本：

- `bash ./run_remote.sh`

脚本会：

- 以 `--gpus all` 启动容器；
- 固定 `DISPLAY=:1`；
- 将 VNC 映射到 `127.0.0.1:5901`；
- 挂载 checkpoints/logs 与 `~/.mujoco`。

### 3) 验证 IsaacGym（先 headless，再 viewer）

进入容器：

- `docker exec -it rl-vgl bash`

先做 CUDA/设备自检：

- `conda run -n rl python -c "import torch; print(torch.__version__); print(torch.cuda.is_available()); print(torch.cuda.get_device_name(0))"`

再跑 Cartpole（headless）：

- `cd /workspace/IsaacGymEnvs`
- `conda run -n rl python ./isaacgymenvs/train.py task=Cartpole sim_device=cuda:0 rl_device=cuda:0 headless=True max_iterations=50`

最后跑 Cartpole（viewer）：

- `export DISPLAY=:1`
- `cd /workspace/IsaacGymEnvs`
- `conda run -n rl python ./isaacgymenvs/train.py task=Cartpole sim_device=cuda:0 rl_device=cuda:0 headless=False max_iterations=50`

验收标准：

- 不出现 `no kernel image is available`；
- 训练可进入迭代；
- viewer 可见仿真画面。

### 4) 验证 MuJoCo（simulate）

仍在容器内执行：

- `cd /root/.mujoco/mujoco210/bin`
- `./simulate ../model/humanoid.xml`

说明：

- 若命令找不到，请先确认宿主机 `~/.mujoco` 已正确挂载到容器 `/root/.mujoco`；
- 若是远端图形会话，确保 `DISPLAY=:1` 与 VNC 会话正常。

### 5) 在本机查看（SSH 隧道 + VNC）

在你的本机（不是服务器）执行端口转发：

- `ssh -N -L 5901:127.0.0.1:5901 <user>@<server_ip>`

然后本机 VNC 客户端连接：

- `127.0.0.1:5901`

连接成功后可直接看到容器内桌面与 IsaacGym/MuJoCo 窗口。

### 6) 失败时最小排查

- 容器状态：`docker ps -a | grep rl-vgl`
- VNC 日志：`docker logs rl-vgl --tail 200`
- GPU 可见性：`docker exec -it rl-vgl nvidia-smi`
- 训练脚本快速回归：`docker exec -it rl-vgl bash -lc 'cd /workspace && ./gpu_smoke_test.sh'`
