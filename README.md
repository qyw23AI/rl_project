# RL Project (Isaac Gym + MuJoCo + VirtualGL + TurboVNC)

本仓库已包含你要求的依赖与流程：

新手逐步学习与验收文档： [understand.md](understand.md)

## 1) PyTorch 与 Python 依赖

- 已在 [requirements.txt](requirements.txt) 中包含：
  - `torch==1.11.0+cu113`
  - `torchvision==0.12.0+cu113`
  - `pyquaternion` `pyyaml` `pexpect` `matplotlib` `einops` `tqdm` `packaging`
  - `h5py` `ipython` `getkey` `wandb` `chardet`
  - `numpy==1.23.2` `h5py_cache` `opencv-python`
  - `tensorboard` `onnxruntime` `mujoco-python-viewer` `scipy` `gym` `mujoco-py`
- 镜像中通过 `python3-pip` 安装 pip，并配置清华镜像源。

## 2) Isaac Gym 安装与验证

- [IsaacGymEnvs](IsaacGymEnvs) 已作为 Git 子模块管理；克隆后请执行：
  - `git submodule update --init --recursive`

- [Dockerfile](Dockerfile) 已包含可编辑安装逻辑：
  - `conda run -n rl pip install -e /workspace/isaacgym1/isaacgym/python`
  - `conda run -n rl pip install -e /workspace/IsaacGymEnvs`
- 若源码目录不完整，构建时会给出 warning 并跳过，避免直接失败。

手动流程（与你给出的命令一致）：

- `git clone https://github.com/isaac-sim/IsaacGymEnvs.git`
- `conda activate rl`
- `pip install -e ./isaacgym1/isaacgym/python`
- `pip install -e ./IsaacGymEnvs`

验证命令（容器内，建议在 `rl` 环境）：

- `conda run -n rl python -c 'import isaacgym; print("isaacgym ok")'`
- `conda run -n rl python ./IsaacGymEnvs/isaacgymenvs/train.py task=Cartpole`

## 3) MuJoCo 安装与验证

- [run_remote.sh](run_remote.sh) 已包含：
  - 检查 `~/.mujoco/mjkey.txt` 是否存在（不存在直接退出）
  - 按需下载并解压 `mujoco210-linux-x86_64.tar.gz` 到 `~/.mujoco`
- 容器运行时会挂载 `~/.mujoco:/root/.mujoco:ro`。
- 若需要手动设置：
  - `export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/root/.mujoco/mujoco210/bin`

MuJoCo 本地测试（宿主机手动流程）可参考：

- `cd ~/.mujoco/mujoco210/bin`
- `./simulate ../model/humanoid.xml`

## 安全说明

- 不要把 `mjkey.txt` 或任何私钥写入仓库或镜像。
- 不要将 VNC 端口直接暴露公网，建议使用 SSH 隧道。
