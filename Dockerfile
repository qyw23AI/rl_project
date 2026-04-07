# syntax=docker/dockerfile:1
# 目标：在单容器内提供 Isaac Gym + MuJoCo + VirtualGL + TurboVNC 环境
# 基础镜像升级为 CUDA 12.1 + Ubuntu 22.04，以匹配 4090 目标栈（Torch 2.4+ / cu121）。
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

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
    libpython3.8 \
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

# 为了支持 isaacgym gym_38.so（Python 3.8 编译的二进制），
# 从 Ubuntu 20.04 源补充 libpython3.8 库（Ubuntu 22.04 已移除该版本）。
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl; \
    mkdir -p /tmp/py38; \
    cd /tmp/py38; \
    curl -L -o libpython3.8.deb "http://mirrors.aliyun.com/ubuntu/pool/main/p/python3.8/libpython3.8_3.8.10-0ubuntu1~20.04.9_amd64.deb" || \
    curl -L -o libpython3.8.deb "http://archive.ubuntu.com/ubuntu/pool/main/p/python3.8/libpython3.8_3.8.10-0ubuntu1~20.04.9_amd64.deb"; \
    dpkg -i libpython3.8.deb || true; \
    rm -rf /tmp/py38; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    echo "[ok] libpython3.8 supplemented for isaacgym gym_38.so support"

# 安装 VirtualGL 与 TurboVNC。
# 说明：下面 URL 为示例版本，可按官方发布页替换为更新版本。
ARG VGL_VERSION=3.1.1
ARG TVNC_VERSION=3.1.2
RUN set -eux; \
    wget -O /tmp/virtualgl.deb "https://github.com/VirtualGL/virtualgl/releases/download/${VGL_VERSION}/virtualgl_${VGL_VERSION}_amd64.deb"; \
    wget -O /tmp/turbovnc.deb "https://github.com/TurboVNC/turbovnc/releases/download/${TVNC_VERSION}/turbovnc_${TVNC_VERSION}_amd64.deb"; \
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
    "${CONDA_DIR}/bin/conda" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main; \
    "${CONDA_DIR}/bin/conda" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r; \
    "${CONDA_DIR}/bin/conda" clean -afy; \
    "${CONDA_DIR}/bin/conda" create -y -n rl python=3.8.10; \
    "${CONDA_DIR}/bin/conda" clean -afy

# 让 conda 可执行文件在 PATH 中可见。
ENV PATH=${CONDA_DIR}/bin:${PATH}

# MuJoCo/图形库常用动态库路径。
# 运行时通过 LD_LIBRARY_PATH 让 Python 扩展更容易找到 GL、MuJoCo 及 NVIDIA 相关库。
ENV MUJOCO_GL=egl \
    LD_LIBRARY_PATH=/opt/conda/envs/rl/lib:/opt/conda/lib:/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}

WORKDIR /workspace

# 先复制 requirements 可利用 Docker 层缓存。
COPY requirements.txt /workspace/requirements.txt
ARG QUICK_DEBUG=0
ARG PIP_USE_CN_MIRROR=1
RUN set -eux; \
    # 可通过 PIP_USE_CN_MIRROR 控制是否启用国内镜像。
    # - 1: 使用清华镜像（无代理或国际链路较慢时通常更稳）
    # - 0: 不使用国内镜像（代理质量较好时通常更快）
    # 注意：torch/torchvision 版本不在此处锁死，交由后续安装链路按 Isaac Gym 兼容性解析。
    if [ "${PIP_USE_CN_MIRROR}" = "1" ]; then \
        echo "[pip] use CN mirror: tuna"; \
        conda run -n rl python -m pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple; \
        conda run -n rl python -m pip config set global.trusted-host pypi.tuna.tsinghua.edu.cn; \
    else \
        echo "[pip] use default index (proxy-friendly mode)"; \
        conda run -n rl python -m pip config unset global.index-url || true; \
        conda run -n rl python -m pip config unset global.trusted-host || true; \
    fi; \
    awk 'BEGIN{skip=0} /^-f[[:space:]]/{next} /^torch([<=>]|$)/{next} /^torchvision([<=>]|$)/{next} {print}' /workspace/requirements.txt > /tmp/requirements_light.txt; \
    awk '/^torch([<=>]|$)|^torchvision([<=>]|$)/' /workspace/requirements.txt > /tmp/requirements_heavy.txt; \
    TORCH_FIND_LINKS="$(awk '/^-f[[:space:]]/{print $2; exit}' /workspace/requirements.txt)"; \
    echo "[pip] phase-1(light deps) start"; \
    while IFS= read -r requirement; do \
        case "$requirement" in \
            ""|\#*) continue ;; \
            *) \
                echo "[pip] installing: ${requirement}"; \
                conda run -n rl python -m pip install --no-cache-dir --retries 20 --default-timeout 120 --progress-bar on -v "${requirement}" || { echo "[pip][error] failed on: ${requirement}"; exit 1; }; \
                ;; \
        esac; \
    done < /tmp/requirements_light.txt; \
    if [ "${QUICK_DEBUG}" = "1" ]; then \
        echo "[pip] QUICK_DEBUG=1: skip heavy deps (torch/torchvision) for fast troubleshooting"; \
    else \
        echo "[pip] phase-2(heavy deps: torch/torchvision) start"; \
        while IFS= read -r requirement; do \
            case "$requirement" in \
                ""|\#*) continue ;; \
                *) \
                    echo "[pip] installing: ${requirement}"; \
                    if [ -n "${TORCH_FIND_LINKS}" ]; then \
                        conda run -n rl python -m pip install --no-cache-dir --retries 20 --default-timeout 120 --progress-bar on -v -f "${TORCH_FIND_LINKS}" "${requirement}" || { echo "[pip][error] failed on: ${requirement}"; exit 1; }; \
                    else \
                        conda run -n rl python -m pip install --no-cache-dir --retries 20 --default-timeout 120 --progress-bar on -v "${requirement}" || { echo "[pip][error] failed on: ${requirement}"; exit 1; }; \
                    fi; \
                    ;; \
            esac; \
        done < /tmp/requirements_heavy.txt; \
    fi; \
    rm -f /tmp/requirements_light.txt /tmp/requirements_heavy.txt; \
    echo "[pip] requirements installation finished"

# 说明：torch/torchvision 版本不在 requirements 中强制锁死，按 Isaac Gym / IsaacGymEnvs 依赖链路解析。

# 再复制项目内容到 /workspace。
COPY . /workspace

# 安装 Isaac Gym / IsaacGymEnvs（可编辑模式）。
# - IsaacGymEnvs 缺失时自动拉取官方仓库。
# - 优先使用上传的 isaacgym 压缩包（issacgym.tar.xz / isaacgym.tar.xz）自动解压安装。
# - 若压缩包不可用，再尝试通过 build-arg ISAACGYM_GIT_URL 拉取。
ARG ISAACGYMENVS_GIT_URL=https://github.com/isaac-sim/IsaacGymEnvs.git
ARG ISAACGYM_GIT_URL=
ARG ISAACGYM_ARCHIVE=/workspace/issacgym.tar.xz
RUN set -eux; \
        if [ ! -f /workspace/IsaacGymEnvs/setup.py ] && [ ! -f /workspace/IsaacGymEnvs/pyproject.toml ]; then \
            echo "[git] IsaacGymEnvs source missing, cloning from ${ISAACGYMENVS_GIT_URL}"; \
            rm -rf /workspace/IsaacGymEnvs; \
            git clone --depth 1 "${ISAACGYMENVS_GIT_URL}" /workspace/IsaacGymEnvs; \
        fi; \
        if [ ! -f /workspace/isaacgym1/isaacgym/python/setup.py ]; then \
            ISAACGYM_ARCHIVE_REAL=""; \
            for c in "${ISAACGYM_ARCHIVE}" /workspace/issacgym.tar.xz /workspace/isaacgym.tar.xz; do \
                if [ -f "$c" ]; then \
                    ISAACGYM_ARCHIVE_REAL="$c"; \
                    break; \
                fi; \
            done; \
            if [ -n "${ISAACGYM_ARCHIVE_REAL}" ]; then \
                echo "[archive] isaacgym source missing, extracting ${ISAACGYM_ARCHIVE_REAL}"; \
                rm -rf /workspace/isaacgym1 /tmp/isaacgym_extract; \
                mkdir -p /tmp/isaacgym_extract /workspace/isaacgym1; \
                tar -xJf "${ISAACGYM_ARCHIVE_REAL}" -C /tmp/isaacgym_extract; \
                ISAACGYM_SETUP_PATH="$(find /tmp/isaacgym_extract -maxdepth 8 -path '*/isaacgym/python/setup.py' | head -n 1 || true)"; \
                if [ -z "${ISAACGYM_SETUP_PATH}" ]; then \
                    echo "[error] cannot find isaacgym/python/setup.py inside ${ISAACGYM_ARCHIVE_REAL}"; \
                    exit 1; \
                fi; \
                ISAACGYM_ROOT_DIR="$(dirname "$(dirname "$(dirname "${ISAACGYM_SETUP_PATH}")")")"; \
                cp -a "${ISAACGYM_ROOT_DIR}/." /workspace/isaacgym1/; \
                rm -rf /tmp/isaacgym_extract; \
            fi; \
        fi; \
        if [ ! -f /workspace/isaacgym1/isaacgym/python/setup.py ] && [ -n "${ISAACGYM_GIT_URL}" ]; then \
            echo "[git] isaacgym source missing, cloning from ${ISAACGYM_GIT_URL}"; \
            rm -rf /workspace/isaacgym1; \
            git clone --depth 1 "${ISAACGYM_GIT_URL}" /workspace/isaacgym1; \
        fi; \
        if [ -f /workspace/isaacgym1/isaacgym/python/setup.py ]; then \
            conda run -n rl python -m pip install --no-deps -e /workspace/isaacgym1/isaacgym/python; \
        else \
            echo "[error] /workspace/isaacgym1/isaacgym/python/setup.py not found."; \
            echo "[hint] Please provide source under /workspace/isaacgym1 or set --build-arg ISAACGYM_GIT_URL=<repo>."; \
            exit 1; \
        fi; \
        if [ -f /workspace/IsaacGymEnvs/setup.py ] || [ -f /workspace/IsaacGymEnvs/pyproject.toml ]; then \
            echo "[pip] installing IsaacGymEnvs in editable mode"; \
            conda run -n rl python -m pip install --no-deps -v -e /workspace/IsaacGymEnvs; \
            echo "[pip] IsaacGymEnvs editable install finished"; \
        else \
            echo "[error] /workspace/IsaacGymEnvs project metadata not found."; \
            exit 1; \
        fi; \
        conda run -n rl python -m pip freeze > /workspace/requirements.freeze.txt; \
        echo "[pip] freeze written to /workspace/requirements.freeze.txt"

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
