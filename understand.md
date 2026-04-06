# Docker 新手学习手册（逐步确认版）

这份文档用于“边学边验收”你的镜像构建流程。建议按顺序执行，每一步都先理解“为什么”，再看“怎么做”。

---

## 0. 先看项目里每个文件负责什么

- 镜像配方： [Dockerfile](Dockerfile)
- 容器启动逻辑（VNC/VirtualGL）： [docker_entrypoint.sh](docker_entrypoint.sh)
- Python 依赖清单： [requirements.txt](requirements.txt)
- 构建上下文过滤： [.dockerignore](.dockerignore)
- 本地构建+测试+推送： [build_and_push.sh](build_and_push.sh)
- 服务器一键拉取/构建/运行： [run_remote.sh](run_remote.sh)
- GitHub 自动构建推送： [.github/workflows/docker-build.yml](.github/workflows/docker-build.yml)

补充：`IsaacGymEnvs` 已作为子模块，首次拉取后需要执行 `git submodule update --init --recursive`。

---

## 1. 学会读 Dockerfile（最重要）

### 1.1 基础镜像

- 入口： [Dockerfile](Dockerfile#L4)
- 含义：用 NVIDIA 官方 CUDA 11.8 + Ubuntu 22.04 作为基础，保留你要求的 22.04，同时使用一个 Docker Hub 上可正常拉取的组合。

### 1.2 环境变量

- 位置： [Dockerfile](Dockerfile#L6-L9)
- 作用：
  - `DEBIAN_FRONTEND=noninteractive` 避免 apt 安装时进入交互。
  - `LANG/LC_ALL` 统一编码，减少中文/日志乱码。

### 1.3 系统依赖安装

- 位置： [Dockerfile](Dockerfile#L21-L47)
- 你要确认：
  - 有 `python3-pip`（满足你的 pip 安装要求）
  - 有 OpenGL/X11 相关库（供 MuJoCo/Isaac Gym 图形渲染）
  - 有 `build-essential`（编译 Python 扩展需要）

### 1.4 VirtualGL + TurboVNC 安装

- 位置： [Dockerfile](Dockerfile#L50-L58)
- 作用：
  - VirtualGL 负责把 GPU 渲染转发到远端桌面。
  - TurboVNC 提供远程图形会话。

### 1.5 MuJoCo 与动态库路径

- 位置： [Dockerfile](Dockerfile#L62-L63)
- 作用：
  - `MUJOCO_GL=egl`：优先使用 EGL 路径（更适合无物理显示器场景）。
  - `LD_LIBRARY_PATH`：让运行时能找到 CUDA/GL/MuJoCo 动态库。

### 1.6 pip 源和依赖安装

- 位置： [Dockerfile](Dockerfile#L69-L75)
- 你要理解：
   - 已安装 Miniconda 并创建 `rl` 环境（Python 3.8.10）。
   - `rl` 环境内配置了清华镜像加速。
   - 依赖由 [requirements.txt](requirements.txt) 统一管理，可复现。

### 1.7 可编辑安装 Isaac Gym/IsaacGymEnvs

- 位置： [Dockerfile](Dockerfile#L80-L91)
- 作用：
  - `pip install -e` 表示“源码可编辑安装”，改代码后无需重装包。
  - 若源码目录暂缺，会输出 warning 而不是让构建直接失败。

### 1.8 容器启动命令

- 位置： [Dockerfile](Dockerfile#L114)
- 含义：容器启动后执行 [docker_entrypoint.sh](docker_entrypoint.sh)。

---

## 2. 学会读启动脚本 docker_entrypoint.sh

### 2.1 严格模式

- 位置： [docker_entrypoint.sh](docker_entrypoint.sh#L2)
- 含义：`set -euo pipefail` 让脚本尽早失败，减少“悄悄出错”。

### 2.2 初始化 VirtualGL

- 位置： [docker_entrypoint.sh](docker_entrypoint.sh#L17-L27)
- 作用：首次运行配置 `vglserver_config`，并对非交互返回码做容错。

### 2.3 启动 VNC（24-bit）

- 位置： [docker_entrypoint.sh](docker_entrypoint.sh#L37)
- 重点：`-depth 24` 可减少 OpenGL 黑屏/花屏问题。

### 2.4 保持容器前台运行

- 位置： [docker_entrypoint.sh](docker_entrypoint.sh#L50)
- 原理：`tail -f` 持续跟踪日志，让容器不退出。

---

## 3. 你关心的 Python 依赖是否都包含

直接看 [requirements.txt](requirements.txt)：

- PyTorch + cu113： [requirements.txt](requirements.txt#L4-L5)
- MuJoCo Python 绑定： [requirements.txt](requirements.txt#L8)
- 你列出的常用包区： [requirements.txt](requirements.txt#L11-L31)

说明：你给的依赖已经并入统一依赖文件，构建镜像时会自动安装。

---

## 4. 本地“学习式”构建流程（推荐按检查点走）

### 检查点 A：只构建，不运行

- 用 `docker build --progress=plain -t <your_image> .`
- 目标：先确认 Dockerfile 每层都能通过。
- 对照文件： [build_and_push.sh](build_and_push.sh#L11)

### 检查点 B：验证 GPU 可见

- 用 `docker run --gpus all --rm <your_image> python3 -c "import torch; print(torch.cuda.is_available())"`
- 用 `docker run --gpus all --rm <your_image> conda run -n rl python -c "import torch; print(torch.cuda.is_available())"`
- 期望输出：`True`
- 对照文件： [build_and_push.sh](build_and_push.sh#L15)

### 检查点 C：再推送镜像

- 对照流程：
  - 打标签 [build_and_push.sh](build_and_push.sh#L17-L18)
  - 推送 [build_and_push.sh](build_and_push.sh#L21)

---

## 5. 服务器一键部署脚本怎么读（最新版）

看 [run_remote.sh](run_remote.sh)：

1. 拉取代码（存在就 `pull`，不存在就 `clone`）
2. 同步并更新子模块（含并行 jobs）
3. 检查 MuJoCo key（缺失时 warning，不中断流程）
4. 按需下载 MuJoCo 2.1.0（带重试、超时、断点续传）
5. 构建镜像（默认 `DOCKER_BUILDKIT=0`，用于规避慢网下 `docker/dockerfile:1` 拉取超时）
6. 启动容器（GPU、`--shm-size=4g`、挂载 `~/.mujoco`、`checkpoints/logs` 持久化、用户映射）
7. 输出 SSH 隧道与训练验证命令

补充：如果你明确需要 BuildKit，可运行前设置 `DOCKER_BUILDKIT_MODE=1`。

---

## 6. CI 自动构建工作流怎么读

看 [.github/workflows/docker-build.yml](.github/workflows/docker-build.yml)：

- 触发条件：push 到 `main` [docker-build.yml](.github/workflows/docker-build.yml#L3-L6)
- Buildx： [docker-build.yml](.github/workflows/docker-build.yml#L19)
- 登录仓库（Secrets）： [docker-build.yml](.github/workflows/docker-build.yml#L25-L28)
- 构建并推送： [docker-build.yml](.github/workflows/docker-build.yml#L31-L35)

---

## 7. 新手最容易踩的坑（重点）

1. `mjkey.txt` 放进仓库或镜像层（高风险）
   - 正确做法：只放宿主机 `~/.mujoco`，运行时挂载。
2. 忘记 `--shm-size=4g`
   - 表现：训练随机崩溃或 DataLoader/仿真异常。
3. VNC 用了非 24-bit 色深
   - 表现：黑屏/渲染错乱。
4. 直接公网开放 5901
   - 正确做法：绑定 `127.0.0.1` + SSH 隧道。

---

## 8. 一次完整验收（建议）

按下面顺序逐步确认：

1. 构建镜像成功（无报错）
2. GPU 检测输出 `True`
3. 进入容器后 `import isaacgym` 成功
4. 能运行 Cartpole 训练
5. VNC 可连接并看到图形
6. MuJoCo 示例可启动

如果你希望，我可以继续为你做“第二版”：在每个脚本中再加入更细粒度行内注释（逐命令解释），并保持与当前逻辑完全一致。

---

## 9. 从零到可训练：完整执行手册（可复制）

### 阶段 A：服务器基础能力

1. 安装 Docker + GPU runtime：
   - `sudo bash ./install_docker_gpu.sh`
2. 重新登录 SSH（让 docker group 生效）
3. 验证：
   - `docker --version`
   - `docker compose version`
   - `docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi`

### 阶段 B：网络加速（强烈建议）

1. 服务器执行：
   - `sudo bash ./enable_mirror_acceleration.sh`
2. 若仍慢，使用本机代理转发：
   - 本机执行：`SSH_TARGET=<user>@<server_ip> LOCAL_PROXY_PORT=7890 ./proxy_forward.sh`
   - 服务器执行：
     - `export HTTP_PROXY=http://127.0.0.1:17890`
     - `export HTTPS_PROXY=http://127.0.0.1:17890`

### 阶段 C：一键构建运行

1. 服务器执行：`./run_remote.sh`
2. 若成功，会得到 VNC 隧道提示
3. 本机执行：`ssh -N -L 5901:127.0.0.1:5901 <user>@<server_ip>`

### 阶段 D：容器内验证训练

1. `conda run -n rl python -c 'import isaacgym; print("isaacgym ok")'`
2. `conda run -n rl python ./IsaacGymEnvs/isaacgymenvs/train.py task=Cartpole`

---

## 10. 关键报错速查表

### 报错 A：`docker: command not found`

- 结论：Docker 未安装或会话未生效
- 处理：执行 [install_docker_gpu.sh](install_docker_gpu.sh)，然后重新登录 SSH

### 报错 B：`failed to resolve source metadata for docker.io/docker/dockerfile:1 ... i/o timeout`

- 结论：到 Docker Hub 的网络超时（常见于慢网/未代理）
- 处理：
  1. 跑 [enable_mirror_acceleration.sh](enable_mirror_acceleration.sh)
  2. 开启 [proxy_forward.sh](proxy_forward.sh)
  3. 确认服务器已导出 `HTTP_PROXY/HTTPS_PROXY`
  4. 重新执行 [run_remote.sh](run_remote.sh)

### 报错 C：子模块下载超时

- 结论：Git 线路不稳
- 处理：代理 + 重试，`run_remote.sh` 已支持并行子模块更新

### 报错 D：容器里无法写 checkpoints/logs

- 结论：目录属主与容器用户不一致
- 处理：使用 `-u $(id -u):$(id -g)`（默认已启用）并在宿主机 `chown`

### 报错 E：MuJoCo 运行库找不到

- 结论：`~/.mujoco` 未挂载或 `mujoco210` 不完整
- 处理：检查挂载与 `~/.mujoco/mujoco210/bin` 是否存在

---

## 11. 现在仓库里每个脚本的定位

- [run_remote.sh](run_remote.sh)：远端一键同步 + 构建 + 运行
- [install_docker_gpu.sh](install_docker_gpu.sh)：Docker + NVIDIA runtime 安装
- [enable_mirror_acceleration.sh](enable_mirror_acceleration.sh)：国内网络加速与镜像配置
- [proxy_forward.sh](proxy_forward.sh)：本机代理转发到远端
- [build_and_push.sh](build_and_push.sh)：本地构建并推送镜像

你按“阶段 A→B→C→D”执行，就能稳定完成全流程。
