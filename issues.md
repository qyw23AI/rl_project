# RL 容器与 Isaac Gym 问题归档（2026-04-07）

## 1) 下载与构建阶段

### 1.1 VirtualGL/TurboVNC 下载 404
- 现象：SourceForge 下载地址失效，构建中断。
- 根因：旧下载链接不可用。
- 处理：改为 GitHub Releases 下载。
- 状态：已解决。

### 1.2 Conda ToS 未接受导致环境创建失败
- 现象：`conda create` 前报 channel terms 未接受。
- 根因：Miniconda 新版对 ToS 有显式要求。
- 处理：在 Dockerfile 里增加 `conda tos accept`。
- 状态：已解决。

### 1.3 Dockerfile RUN 段语法错误
- 现象：`case/while` 语句中断行、反斜杠续行导致 build 失败。
- 根因：Shell 续行格式不完整。
- 处理：修复续行与分支结构。
- 状态：已解决。

## 2) 依赖冲突与安装阶段

### 2.1 `rl-games` 与 `torch` 版本冲突
- 现象：`rl-games==1.6.5` 触发 `torch>=2.2.2`，与 Isaac Gym 旧栈冲突。
- 根因：依赖约束不兼容。
- 处理：回退到 `rl-games==1.6.1`，并通过 requirements 预装依赖，避免 editable 安装时重解析。
- 状态：已解决（CPU 验证通过）。

### 2.2 `isaacgym.tar.xz` 实际是 LFS 指针文本
- 现象：`tar -xJf` 报 `File format not recognized`。
- 根因：文件内容为 Git LFS pointer，而非真实归档。
- 处理：拉取真实二进制后再拷入容器。
- 状态：已解决。

### 2.3 解压后文件名拼写错误
- 现象：使用 `issacgym.tar.xz` 报找不到文件。
- 根因：实际文件名为 `isaacgym.tar.xz`。
- 处理：改为正确文件名。
- 状态：已解决。

### 2.4 `ModuleNotFoundError: No module named 'isaacgym'`
- 现象：训练启动时报找不到 `isaacgym`。
- 根因：当前运行容器未安装 `isaacgym`（重建/重启后状态丢失）。
- 处理：重新从 `/workspace/isaacgym.tar.xz` 解压并 `pip install --no-deps -e /workspace/isaacgym1/python`。
- 状态：已解决。

### 2.5 `RuntimeError: Ninja is required to load C++ extensions`
- 现象：`gymtorch` 编译扩展时失败。
- 根因：缺少 `ninja`。
- 处理：安装 `ninja`。
- 状态：已解决。

## 3) 运行时图形与库加载问题

### 3.1 `ImportError: libpython3.8.so.1.0: cannot open shared object file`
- 现象：`import isaacgym` 失败。
- 根因：动态库搜索路径未覆盖 conda `rl` 环境库目录。
- 处理：运行时导出 `LD_LIBRARY_PATH=/opt/conda/envs/rl/lib:/opt/conda/lib:$LD_LIBRARY_PATH`；Dockerfile 已补默认路径。
- 状态：已解决（当前流程可复现）。

### 3.2 `GLFW initialization failed` / `Failed to create Window`
- 现象：`headless=False` 时 viewer 无法创建。
- 根因：未在有效图形会话中运行，或 VNC 会话未正确启动。
- 处理：
	- 启动并保持 TurboVNC 会话；
	- 运行时设置 `DISPLAY=:1`；
	- 通过 SSH 隧道访问 `127.0.0.1:5901`。
- 状态：已解决（VNC 可连接，CPU 可视化训练已执行成功）。

### 3.3 VNC 启动后立即退出
- 现象：VNC 端口短暂可用后会话消失。
- 根因：
	- 某次容器启动命令绕过 entrypoint；
	- 首次密码交互无人值守失败；
	- 缺失窗口管理器 fallback（TWM）失败。
- 处理：
	- 使用正确启动方式；
	- 显式指定 `xstartup` 启动 XFCE；
	- 临时使用本地隧道场景可用的 `-SecurityTypes None`。
- 状态：已解决（当前 VNC 会话稳定）。

## 4) GPU 兼容性问题（核心未解）

### 4.1 RTX 4090 + 当前 PyTorch 不兼容
- 现象：
	- `NVIDIA GeForce RTX 4090 ... is not compatible with the current PyTorch installation`
	- `CUDA error: no kernel image is available for execution on the device`
	- 后续可能 `Segmentation fault`。
- 根因：当前 Torch/CUDA 构建不含 `sm_89` 内核支持（与 4090 架构不匹配）。
- 处理：目前仅完成 CPU 路径验证；GPU 方案迁移见 [next_step.md](next_step.md)。
- 状态：未解决（待迁移）。

## 5) 当前可用结论

- `isaacgym` 已可导入。
- CPU 训练链路已验证可运行并可保存 checkpoint。
- VNC 可连接并可用于可视化观察（CPU 模式）。
- 4090 原生 GPU 训练仍需升级技术栈。
