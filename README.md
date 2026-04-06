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

## 4) 持久化模型与挂载

为什么要把 `checkpoints`、`logs`、`mjkey` 挂载到宿主机：

- `checkpoints` 需要持久化，避免容器删除后模型丢失。
- `logs` 需要长期保存，方便看 TensorBoard、排查训练曲线与恢复实验。
- `mjkey.txt` 属于敏感文件，应该只保存在宿主机的 `~/.mujoco` 中，并以只读方式挂载进容器。

推荐的宿主目录结构：

- `/home/ubuntu/rl-data/checkpoints`
- `/home/ubuntu/rl-data/logs`
- `/home/ubuntu/.mujoco/mjkey.txt`

推荐运行命令（与 [run_remote.sh](run_remote.sh) 保持一致）：

```bash
docker run --gpus all -it --rm \
  -v /home/ubuntu/.mujoco:/root/.mujoco:ro \
  -v /home/ubuntu/rl-data/checkpoints:/workspace/checkpoints \
  -v /home/ubuntu/rl-data/logs:/workspace/logs \
  --shm-size=4g \
  -p 5901:5901 \
  yourrepo/rl-vgl:latest
```

如果你更喜欢 compose，可以先导出 UID/GID，再启动：

```bash
export UID=$(id -u)
export GID=$(id -g)
docker compose up
```

对应示例见 [docker-compose.yml](docker-compose.yml)。

权限问题与解决方法：

- 如果容器里写出的文件在宿主机上是 root 拥有，建议用 `-u $(id -u):$(id -g)` 启动容器。
- 如果目录已经创建为 root，可在宿主机执行：
  - `chown -R $(id -u):$(id -g) /home/ubuntu/rl-data/checkpoints /home/ubuntu/rl-data/logs`

VNC 安全访问方式：

- 建议不要直接把 5901 暴露到公网。
- 推荐 SSH 隧道：`ssh -N -L 5901:127.0.0.1:5901 <user>@<server_ip>`，然后本地 VNC 客户端连接 `127.0.0.1:5901`。

备份与恢复建议：

- 定期用 `rsync` 备份 `checkpoints` 和 `logs`。
- 如果你有云存储，也可以同步到 S3 或对象存储，减少单机故障风险。

## 5) Docker 与 GPU 环境安装

如果远端服务器还没有 Docker，先运行仓库里的安装脚本：

- `sudo bash ./install_docker_gpu.sh`

这个脚本会自动完成：

- 安装 Docker Engine、Docker Compose 插件和 containerd
- 配置 Docker 官方源
- 安装 NVIDIA Container Toolkit
- 执行 `nvidia-ctk runtime configure --runtime=docker`
- 重启 Docker 并做基础验证

安装后请重新登录 SSH 会话，让 `docker` 用户组权限生效，然后检查：

- `docker --version`
- `docker compose version`
- `docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi`

如果你在国内网络环境下拉包较慢，可以先在远端设置代理，再执行 `./run_remote.sh`：

- `export HTTP_PROXY=http://127.0.0.1:7890`
- `export HTTPS_PROXY=http://127.0.0.1:7890`
- `export NO_PROXY=localhost,127.0.0.1,127.0.0.1`

如果你本机开了 VPN/代理，也可以用 SSH 端口转发把代理端口转到服务器，再让上面的环境变量指向本地转发端口。

## 安全说明

- 不要把 `mjkey.txt` 或任何私钥写入仓库或镜像。
- 不要将 VNC 端口直接暴露公网，建议使用 SSH 隧道。
