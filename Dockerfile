# syntax=docker/dockerfile:1
# 目标：在单容器内提供 Isaac Gym + MuJoCo + VirtualGL + TurboVNC 环境
# 基础镜像固定为 CUDA 11.3 + Ubuntu 22.04，以兼容 torch 1.11.0+cu113。
FROM nvidia/cuda:11.3.1-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Etc/UTC

# 安装系统依赖：
# - build-essential: 构建 Python/C++ 扩展时必需（例如 mujoco-py 的本地编译步骤）。
# - python3/python3-pip: Python 运行时与依赖安装器。
# - git: 拉取或管理子仓库（如 IsaacGymEnvs）时常用。
# - wget/ca-certificates: 下载并校验 VirtualGL/TurboVNC 的安装包。
# - libgl1/libglu1-mesa/libosmesa6/libxext6/libxrender1/libsm6/libglew2.2: OpenGL/离屏渲染与图形库依赖。
# - patchelf: 处理部分二进制库的 RPATH/ELF 修补场景。
# - xfce4/xfce4-terminal/dbus-x11: 提供轻量桌面会话给 VNC 使用。
# - xauth/x11vnc/xterm: X11 认证与远程图形工具。
# - libglvnd0/libglx-mesa0: GLVND/GLX 运行时支持。
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    python3 \
    python3-pip \
    python3-setuptools \
    python3-dev \
    bzip2 \
    git \
    wget \
    ca-certificates \
    patchelf \
    libgl1 \
    libglu1-mesa \
    libosmesa6 \
    libxext6 \
    libxrender1 \
    libsm6 \
    libglew2.2 \
    libglvnd0 \
    libglx-mesa0 \
    xfce4 \
    xfce4-terminal \
    dbus-x11 \
    xauth \
    x11vnc \
    xterm \
    && rm -rf /var/lib/apt/lists/*

# 安装 VirtualGL 与 TurboVNC。
# 说明：下面 URL 为示例版本，可按官方发布页替换为更新版本。
ARG VGL_VERSION=3.1.1
ARG TVNC_VERSION=3.1.2
RUN set -eux; \
    wget -O /tmp/virtualgl.deb "https://sourceforge.net/projects/virtualgl/files/${VGL_VERSION}/virtualgl_${VGL_VERSION}_amd64.deb/download"; \
    wget -O /tmp/turbovnc.deb "https://sourceforge.net/projects/turbovnc/files/${TVNC_VERSION}/turbovnc_${TVNC_VERSION}_amd64.deb/download"; \
    apt-get update; \
    apt-get install -y /tmp/virtualgl.deb /tmp/turbovnc.deb; \
    rm -f /tmp/virtualgl.deb /tmp/turbovnc.deb; \
    rm -rf /var/lib/apt/lists/*

# 安装 Miniconda（按你给的步骤自动化）：
# wget Miniconda 安装脚本 -> 执行静默安装 -> 创建 rl 环境。
ARG CONDA_DIR=/opt/conda
RUN set -eux; \
    wget -O /tmp/Miniconda3-latest-Linux-x86_64.sh "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"; \
    chmod +x /tmp/Miniconda3-latest-Linux-x86_64.sh; \
    /tmp/Miniconda3-latest-Linux-x86_64.sh -b -p "${CONDA_DIR}"; \
    rm -f /tmp/Miniconda3-latest-Linux-x86_64.sh; \
    "${CONDA_DIR}/bin/conda" clean -afy; \
    "${CONDA_DIR}/bin/conda" create -y -n rl python=3.8.10; \
    "${CONDA_DIR}/bin/conda" clean -afy

# 让 conda 可执行文件在 PATH 中可见。
ENV PATH=${CONDA_DIR}/bin:${PATH}

# MuJoCo/图形库常用动态库路径。
# 运行时通过 LD_LIBRARY_PATH 让 Python 扩展更容易找到 GL、MuJoCo 及 NVIDIA 相关库。
ENV MUJOCO_GL=egl \
    LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}

WORKDIR /workspace

# 先复制 requirements 可利用 Docker 层缓存。
COPY requirements.txt /workspace/requirements.txt
RUN conda run -n rl python -m pip install --upgrade pip && \
        # 统一设置 pip 国内镜像（清华源）以提升中国大陆网络环境下的安装稳定性。
        # 注意：torch/torchvision 的 cu113 轮子仍通过 requirements.txt 顶部的 -f 源解析。
    conda run -n rl python -m pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple && \
    conda run -n rl python -m pip config set global.trusted-host pypi.tuna.tsinghua.edu.cn && \
    conda run -n rl python -m pip install --no-cache-dir -r /workspace/requirements.txt

# 关于你给出的 conda pytorch 命令说明：
# - 你给的示例是：conda install pytorch torchvision pytorch-cuda=12.1.0 -c pytorch -c nvidia
# - 但当前基础镜像为 CUDA 11.3，因此此镜像内采用 torch==1.11.0+cu113（与 CUDA 11.3 对齐）更稳妥。
# - 若你要切换到 pytorch-cuda=12.1，请同步把基础镜像升级到 CUDA 12.x。

# 再复制项目内容到 /workspace。
COPY . /workspace

# 安装 Isaac Gym / IsaacGymEnvs（可编辑模式），以便直接在源码目录调试。
# 如果源码尚未放入对应目录，则跳过并给出提示（避免镜像构建硬失败）。
RUN set -eux; \
        if [ -f /workspace/isaacgym1/isaacgym/python/setup.py ]; then \
            conda run -n rl python -m pip install -e /workspace/isaacgym1/isaacgym/python; \
        else \
            echo "[warn] /workspace/isaacgym1/isaacgym/python/setup.py not found, skip editable isaacgym install."; \
        fi; \
        if [ -f /workspace/IsaacGymEnvs/setup.py ] || [ -f /workspace/IsaacGymEnvs/pyproject.toml ]; then \
            conda run -n rl python -m pip install -e /workspace/IsaacGymEnvs; \
        else \
            echo "[warn] /workspace/IsaacGymEnvs project metadata not found, skip editable IsaacGymEnvs install."; \
        fi

# MuJoCo 2.1.0 运行时提示（与用户手动命令保持一致）：
# - 可在宿主机执行：
#   wget https://mujoco.org/download/mujoco210-linux-x86_64.tar.gz
#   tar -zxvf mujoco210-linux-x86_64.tar.gz -C ~/.mujoco
# - 运行容器时挂载 ~/.mujoco 到 /root/.mujoco，并保留 LD_LIBRARY_PATH。
# - 不要把 mjkey.txt 写入镜像层或仓库。

# 关键安全说明：
# 1) 不要把 mjkey.txt 写入镜像层（会永久进入镜像历史）。
# 2) 必须在运行容器时挂载 ~/.mujoco 到 /root/.mujoco，例如：
#    -v ~/.mujoco:/root/.mujoco:ro
# 3) 大模型/数据集也不应 COPY 到镜像，应在运行时挂载。

# 关于运行参数的建议：
# - --shm-size=4g（或更大）：深度学习/仿真进程常使用共享内存，默认 64MB 容易导致崩溃。
# - vncserver -depth 24：24-bit 色深在 OpenGL/VirtualGL 组合下通常更稳定，避免黑屏或渲染异常。
# - 保持 LD_LIBRARY_PATH：减少 OpenGL、MuJoCo、CUDA 动态库加载失败风险。

# 持久化与挂载说明：
# - 不要把 mjkey.txt、模型文件、训练产物直接写入镜像；镜像应该保持可复现但尽量“无状态”。
# - 运行时请通过 `-v` 把宿主机目录挂载到容器内，例如：
#   -v /home/ubuntu/.mujoco:/root/.mujoco:ro
#   -v /home/ubuntu/rl-data/checkpoints:/workspace/checkpoints
#   -v /home/ubuntu/rl-data/logs:/workspace/logs
# - 其中 `/root/.mujoco` 存放 MuJoCo license/key 与运行库；对 `mjkey.txt` 使用 `:ro` 只读挂载更安全。
# - `/workspace/checkpoints` 用于保存模型权重，避免容器删除后丢失训练结果。
# - `/workspace/logs` 用于保存 tensorboard 与训练日志，便于调试、对比和恢复。
# - 推荐的运行命令模板请直接按下面示例替换宿主机路径和镜像名：
#   docker run --gpus all -it --rm \
#     -v /home/ubuntu/.mujoco:/root/.mujoco:ro \
#     -v /home/ubuntu/rl-data/checkpoints:/workspace/checkpoints \
#     -v /home/ubuntu/rl-data/logs:/workspace/logs \
#     --shm-size=4g \
#     -p 5901:5901 \
#     yourrepo/rl-vgl:latest

COPY docker_entrypoint.sh /usr/local/bin/docker_entrypoint.sh
RUN chmod +x /usr/local/bin/docker_entrypoint.sh

CMD ["/usr/local/bin/docker_entrypoint.sh"]
