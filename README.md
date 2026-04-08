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
- 当前镜像基座已调整为 `nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04`，以保留 Ubuntu 22.04，同时使用可正常拉取的 CUDA 22.04 组合。

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
  - 检查 `~/.mujoco/mjkey.txt` 是否存在（不存在会 warning 并继续）
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
- 默认 VNC 密码为 `rlvnc123`，也可以在启动前用 `VNC_PASSWORD` 自定义。

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

一键转发脚本见 [proxy_forward.sh](proxy_forward.sh)：

- 在你电脑本机运行它，不是在服务器上运行。
- 它会把你本机的代理端口通过 SSH 反向转发到服务器上的 `127.0.0.1:17890`。
- 服务器上再导出：`HTTP_PROXY=http://127.0.0.1:17890`、`HTTPS_PROXY=http://127.0.0.1:17890`。
- 例子：`SSH_TARGET=ubuntu@10.60.20.189 LOCAL_PROXY_PORT=7890 ./proxy_forward.sh`
- 然后在服务器里先 `export HTTP_PROXY=http://127.0.0.1:17890`，再执行 `./run_remote.sh`

## 6) 服务器网络加速（推荐先执行）

如果服务器下载很慢，先执行一键加速脚本 [enable_mirror_acceleration.sh](enable_mirror_acceleration.sh)：

- `sudo bash ./enable_mirror_acceleration.sh`

脚本会尽可能配置以下加速项：

- APT：切换 TUNA 镜像源并启用重试/超时参数
- Docker：配置 registry mirrors（保留已有 NVIDIA runtime 配置）
- pip：配置清华源、超时与重试
- conda：配置清华镜像 channels
- git：调优慢网参数（降低超时中断概率）

推荐顺序：

1. 本机开代理并运行 [proxy_forward.sh](proxy_forward.sh)
2. 服务器执行 `export HTTP_PROXY=http://127.0.0.1:17890` 与 `export HTTPS_PROXY=http://127.0.0.1:17890`
3. 服务器执行 `sudo bash ./enable_mirror_acceleration.sh`
4. 服务器执行 `./run_remote.sh`

## 7) 一键全流程（推荐执行顺序）

下面是当前仓库的完整实操顺序（本机 + 服务器）：

1. 服务器安装 Docker 与 GPU runtime：
  - `sudo bash ./install_docker_gpu.sh`
2. （可选）本机打开代理转发到服务器：
  - `SSH_TARGET=<user>@<server_ip> LOCAL_PROXY_PORT=7890 ./proxy_forward.sh`
3. 服务器导出代理环境变量（如使用转发）：
  - `export HTTP_PROXY=http://127.0.0.1:17890`
  - `export HTTPS_PROXY=http://127.0.0.1:17890`
4. 服务器配置镜像加速：
  - `sudo bash ./enable_mirror_acceleration.sh`
5. 服务器执行一键构建与运行：
  - `./run_remote.sh`
6. 本机通过 SSH 隧道访问 VNC：
  - `ssh -N -L 5901:127.0.0.1:5901 <user>@<server_ip>`

### run_remote.sh 详细使用方法

脚本入口： [run_remote.sh](run_remote.sh)

当前脚本支持三种常见模式：

1. 首次部署（构建 + 新建并启动容器）
  - `bash ./run_remote.sh`

2. 只启动已有容器（不重建镜像）
  - `SKIP_BUILD=1 bash ./run_remote.sh`
  - 适用场景：你已经有可用镜像，只想快速把容器拉起来。

3. 强制重建容器（可选是否跳过构建）
  - 重建镜像并重建容器：
    - `RECREATE_CONTAINER=1 bash ./run_remote.sh`
  - 不构建镜像，仅删除旧容器并基于现有镜像重建：
    - `SKIP_BUILD=1 RECREATE_CONTAINER=1 bash ./run_remote.sh`

脚本对容器存在状态的行为：

- 若容器不存在：执行 `docker run` 新建并启动。
- 若容器已存在且运行中：脚本直接提示“已运行”并退出。
- 若容器已存在但未运行：脚本执行 `docker start`。
- 若设置 `RECREATE_CONTAINER=1`：先 `docker rm -f` 再新建容器。

常用环境变量（建议按需覆盖）：

- `IMAGE`：镜像名，默认 `rl-vgl:latest`
- `CONTAINER_NAME`：容器名，默认 `rl-vgl`
- `SKIP_BUILD`：是否跳过构建（`1` 跳过，默认 `0`）
- `RECREATE_CONTAINER`：是否强制删旧容器重建（`1` 开启，默认 `0`）
- `DOCKER_BUILDKIT_MODE`：构建器模式（默认 `0`，即 legacy builder）
- `DOCKER_BUILD_PROGRESS`：BuildKit 日志模式（默认 `plain`）
- `QUICK_DEBUG`：依赖快速调试开关（默认 `0`）
- `PIP_USE_CN_MIRROR`：pip 国内镜像开关（默认 `1`）
- `HOST_CHECKPOINT_DIR`：宿主机 checkpoint 挂载目录
- `HOST_LOG_DIR`：宿主机 logs 挂载目录

常见示例：

```bash
# 仅启动现有容器
SKIP_BUILD=1 bash ./run_remote.sh

# 镜像名/容器名自定义 + 仅启动
IMAGE=myrepo/rl-vgl:latest CONTAINER_NAME=rl-vgl-dev SKIP_BUILD=1 bash ./run_remote.sh

# 强制重建容器，但不重建镜像
SKIP_BUILD=1 RECREATE_CONTAINER=1 bash ./run_remote.sh

# 首次构建时使用 BuildKit
DOCKER_BUILDKIT_MODE=1 DOCKER_BUILD_PROGRESS=plain bash ./run_remote.sh
```

注意：

- `SKIP_BUILD=1` 时，若本地不存在 `IMAGE`，脚本会报错退出并提示先构建。
- 脚本默认把 VNC 映射到 `127.0.0.1:5901`，建议继续通过 SSH 隧道访问，不要直接暴露公网端口。

## 8) 脚本职责总览

- [install_docker_gpu.sh](install_docker_gpu.sh)
  - 安装 Docker Engine、Compose 插件、NVIDIA Container Toolkit
  - 配置 Docker GPU runtime
- [enable_mirror_acceleration.sh](enable_mirror_acceleration.sh)
  - 配置 APT / Docker / pip / conda / git 慢网优化
- [proxy_forward.sh](proxy_forward.sh)
  - 在本机创建 SSH 反向转发，把本机代理暴露给服务器
- [run_remote.sh](run_remote.sh)
  - 同步代码和子模块、下载 MuJoCo runtime、构建镜像并启动容器
  - 支持 `SKIP_BUILD=1` 仅启动、`RECREATE_CONTAINER=1` 强制重建容器
  - 默认使用 `DOCKER_BUILDKIT=0` 规避 `docker/dockerfile:1` 拉取超时
- [build_and_push.sh](build_and_push.sh)
  - 本地构建、GPU 快测、打 tag 并推送镜像

## 9) 常见报错与定位

1. `docker: command not found`
  - 原因：服务器未安装 Docker 或未在 PATH
  - 处理：执行 [install_docker_gpu.sh](install_docker_gpu.sh)

2. `failed to resolve source metadata for docker.io/docker/dockerfile:1: ... i/o timeout`
  - 原因：到 Docker Hub 网络超时（BuildKit 前端镜像拉取失败）
  - 处理：
    - 先跑 [enable_mirror_acceleration.sh](enable_mirror_acceleration.sh)
    - 使用 [proxy_forward.sh](proxy_forward.sh) + `HTTP_PROXY/HTTPS_PROXY`
    - 当前 [run_remote.sh](run_remote.sh) 已默认回退到 legacy builder

3. 子模块拉取慢或中断
  - 原因：跨境网络抖动
  - 处理：
    - 保持代理开启
    - 重新执行 `./run_remote.sh`（已启用子模块并行拉取）

4. 容器启动后 MuJoCo 相关报错
  - 原因：`~/.mujoco` 未挂载或运行库未下载完整
  - 处理：确认 `-v ${HOME}/.mujoco:/root/.mujoco:ro`，并检查 `~/.mujoco/mujoco210`

5. 宿主机目录权限问题（checkpoints/logs 无法写入）
  - 原因：容器用户与宿主目录属主不一致
  - 处理：
    - 使用 `-u $(id -u):$(id -g)`（已在 [run_remote.sh](run_remote.sh) 默认启用）
    - 宿主机执行 `chown -R $(id -u):$(id -g) /home/ubuntu/rl-data/checkpoints /home/ubuntu/rl-data/logs`

## 10) 验证清单（一次性验收）

- `docker --version` 正常
- `docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi` 正常
- `./run_remote.sh` 构建并启动成功
- 进入容器后：
  - `conda run -n rl python -c 'import isaacgym; print("isaacgym ok")'`
  - `conda run -n rl python ./IsaacGymEnvs/isaacgymenvs/train.py task=Cartpole`

## 安全说明

- 不要把 `mjkey.txt` 或任何私钥写入仓库或镜像。
- 不要将 VNC 端口直接暴露公网，建议使用 SSH 隧道。
