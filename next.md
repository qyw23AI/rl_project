### 提示词 1 更新 Dockerfile 添加挂载说明与运行时提示

text

```
### 目标文件: Dockerfile（在仓库根）
请修改现有 Dockerfile，**只添加注释与运行时提示**，不要改变镜像构建逻辑。要求：
- 在文件顶部或合适位置添加一段注释，说明**不要把 mjkey.txt 或模型文件写入镜像**，并明确说明运行容器时应通过 `-v` 将宿主机目录挂载到容器内（给出示例路径）。
- 在 Dockerfile 末尾或 CMD 前，添加一行注释示例，展示推荐的运行命令模板（示例）：
```

# 运行示例（在宿主机执行）：

docker run --gpus all -it --rm \

-v /home/ubuntu/.mujoco:/root/.mujoco:ro \

-v /home/ubuntu/rl-data/checkpoints:/workspace/checkpoints \

-v /home/ubuntu/rl-data/logs:/workspace/logs \

--shm-size=4g \

-p 5901:5901 \

yourrepo/rl-vgl:latest

Code

```
- 注释中解释每个挂载的必要性：`~/.mujoco` 为 MuJoCo license 与库，`/workspace/checkpoints` 保存模型，`/workspace/logs` 保存 tensorboard/logs。
- 强调使用 `:ro` 对 mjkey 的只读挂载以提高安全性。
- 输出修改后的 Dockerfile 内容（仅修改注释与示例命令部分）。
```

### 提示词 2 修改 docker_entrypoint.sh 确保挂载目录存在与权限提示

text

```
### 目标文件: docker_entrypoint.sh
请修改或追加脚本逻辑，使 entrypoint 在启动 VNC/服务前：
- 检查并创建容器内的持久化目录（/workspace/checkpoints, /workspace/logs）如果不存在则创建，并设置合适权限（chown/chmod），但不要改变文件属主为 root 的默认行为，提供注释说明如何在运行容器时用 -u 指定 UID。
- 检查 /root/.mujoco/mjkey.txt 是否存在；若不存在，打印清晰错误并退出（exit 1），并给出提示如何在宿主机上传 mjkey 并挂载（示例 scp 命令）。
- 在脚本中加入注释说明：为什么要在 entrypoint 检查目录与 mjkey（避免运行时崩溃与数据丢失）。
- 保持原有 vncserver 启动逻辑不变，只在前面加入这些检查与提示。
请输出完整修改后的 docker_entrypoint.sh 内容。
```

### 提示词 3 更新 run_remote.sh 增加挂载示例与权限建议

text

```
### 目标文件: run_remote.sh
请生成或修改 run_remote.sh，使其成为远端一键构建并运行脚本，要求：
- 在脚本开头检测 ~/.mujoco/mjkey.txt 是否存在，若不存在给出错误并退出。
- 提供构建镜像命令：`docker build -t yourrepo/rl-vgl:latest .`
- 提供运行容器的推荐命令（带挂载）并把占位符替换为变量（IMAGE, HOST_CHECKPOINT_DIR, HOST_LOG_DIR），例如：
```

IMAGE=yourrepo/rl-vgl:latest
HOST_CHECKPOINT_DIR=/home/ubuntu/rl-data/checkpoints
HOST_LOG_DIR=/home/ubuntu/rl-data/logs
docker run --gpus all -it --rm 
-v /root/.mujoco:/root/.mujoco:ro 
-v ${HOST_CHECKPOINT_DIR}:/workspace/checkpoints 
-v ${HOST_LOG_DIR}:/workspace/logs 
--shm-size=4g 
-p 5901:5901 
${IMAGE}

Code

```
- 在脚本中加入说明如何以宿主用户 UID 启动容器以避免权限问题（示例 `-u $(id -u):$(id -g)`），并给出 chown 建议命令。
- 在脚本末尾打印如何通过 SSH 隧道连接 VNC 的示例命令。
- 输出完整 run_remote.sh 内容并在顶部注明需要替换的占位符。
```

### 提示词 4 新增 docker-compose.yml 示例包含挂载与用户映射

text

```
### 目标文件: docker-compose.yml
请生成一个 docker-compose.yml 示例，放在仓库根，要求：
- 服务名为 rl，image 使用占位符 yourrepo/rl-vgl:latest。
- 使用 runtime: nvidia 或 environment 中设置 NVIDIA_VISIBLE_DEVICES（根据 compose 版本选择），并设置 shm_size: '4gb'。
- 在 volumes 中示例绑定：
  - ./checkpoints:/workspace/checkpoints
  - ./logs:/workspace/logs
  - ~/.mujoco:/root/.mujoco:ro
- 提供可选的 user 字段注释，示例 `user: "${UID}:${GID}"` 并在 README 中说明如何在本地导出 UID/GID 环境变量再运行 `docker-compose up`。
- 在文件中加入注释说明每个挂载的用途与安全建议（不要把 mjkey 放入仓库）。
输出完整 docker-compose.yml 内容。
```

### 提示词 5 更新 README 增加挂载与权限说明段落

text

```
### 目标文件: README.md（追加或修改）
请在 README 中新增一个名为 持久化模型与挂载 的段落，要求内容包括：
- 为什么要把 checkpoints/logs/mjkey 挂载到宿主机（持久化、备份、调试）。
- 推荐的宿主目录结构示例：
  /home/ubuntu/rl-data/checkpoints
  /home/ubuntu/rl-data/logs
  /home/ubuntu/.mujoco/mjkey.txt
- 推荐运行命令示例（与 run_remote.sh 保持一致），并说明如何通过 SSH 隧道安全访问 VNC。
- 说明权限问题与解决方法（使用 -u 指定 UID 或在宿主机 chown）。
- 简短的恢复与备份建议（定期 rsync 或上传到 S3）。
输出 README 的新增段落，语言简洁明了，便于直接粘贴。
```
