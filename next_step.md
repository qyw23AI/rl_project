# Next Steps：在 RTX 4090 上真正跑通 GPU 强化学习

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
