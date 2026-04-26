# legged_gym 体系总览（从配置到策略更新）

放在legged_gym下进行使用才好跳转

> 目标：先建立“全局地图”，明确 **配置如何进入环境**、**训练如何采样与更新策略**、**文件之间如何关联**。
> 后续你可以按本文件中的“预留深入解读”逐节补充细节。

---

## 1. 总体架构（一句话）

`legged_gym` 负责 **任务定义 + 物理仿真 + 奖励/观测构建**，`rsl_rl` 负责 **PPO 采样与更新**。两者通过 `VecEnv` 接口对接。

- 环境侧入口： [legged_gym/scripts/train.py](legged_gym/scripts/train.py)
- 任务注册中心： [legged_gym/utils/task_registry.py](legged_gym/utils/task_registry.py)
- 环境实现核心： [legged_gym/envs/base/legged_robot.py](legged_gym/envs/base/legged_robot.py)
- 算法执行核心： [../rsl_rl/rsl_rl/runners/on_policy_runner.py](../rsl_rl/rsl_rl/runners/on_policy_runner.py)
- PPO 更新核心： [../rsl_rl/rsl_rl/algorithms/ppo.py](../rsl_rl/rsl_rl/algorithms/ppo.py)

---

## 2. 目录分层与职责

### 2.1 任务/环境层（legged_gym）

- 任务注册与装配：
  - [legged_gym/envs/__init__.py](legged_gym/envs/__init__.py)
  - [legged_gym/utils/task_registry.py](legged_gym/utils/task_registry.py)
- 基类与主环境：
  - [legged_gym/envs/base/base_task.py](legged_gym/envs/base/base_task.py)
  - [legged_gym/envs/base/legged_robot.py](legged_gym/envs/base/legged_robot.py)
- 配置系统：
  - [legged_gym/envs/base/base_config.py](legged_gym/envs/base/base_config.py)
  - [legged_gym/envs/base/legged_robot_config.py](legged_gym/envs/base/legged_robot_config.py)
  - 示例任务配置：
    - [legged_gym/envs/a1/a1_config.py](legged_gym/envs/a1/a1_config.py)
    - [legged_gym/envs/anymal_c/mixed_terrains/anymal_c_rough_config.py](legged_gym/envs/anymal_c/mixed_terrains/anymal_c_rough_config.py)
    - [legged_gym/envs/anymal_c/flat/anymal_c_flat_config.py](legged_gym/envs/anymal_c/flat/anymal_c_flat_config.py)
- 特化机器人逻辑：
  - [legged_gym/envs/anymal_c/anymal.py](legged_gym/envs/anymal_c/anymal.py)（执行器网络）
  - [legged_gym/envs/cassie/cassie.py](legged_gym/envs/cassie/cassie.py)
- 地形/工具：
  - [legged_gym/utils/terrain.py](legged_gym/utils/terrain.py)
  - [legged_gym/utils/helpers.py](legged_gym/utils/helpers.py)
  - [legged_gym/utils/logger.py](legged_gym/utils/logger.py)

### 2.2 算法层（rsl_rl）

- 环境抽象接口： [../rsl_rl/rsl_rl/env/vec_env.py](../rsl_rl/rsl_rl/env/vec_env.py)
- Runner（训练总循环）： [../rsl_rl/rsl_rl/runners/on_policy_runner.py](../rsl_rl/rsl_rl/runners/on_policy_runner.py)
- PPO 算法： [../rsl_rl/rsl_rl/algorithms/ppo.py](../rsl_rl/rsl_rl/algorithms/ppo.py)
- 策略/价值网络： [../rsl_rl/rsl_rl/modules/actor_critic.py](../rsl_rl/rsl_rl/modules/actor_critic.py)
- 采样缓存（rollout buffer）： [../rsl_rl/rsl_rl/storage/rollout_storage.py](../rsl_rl/rsl_rl/storage/rollout_storage.py)

---

## 3. 从“配置”到“训练”的完整链路

## 3.1 第 0 步：启动入口与参数

入口脚本： [legged_gym/scripts/train.py](legged_gym/scripts/train.py)

核心调用：

1. `task_registry.make_env(...)` 创建环境
2. `task_registry.make_alg_runner(...)` 创建 PPO runner
3. `ppo_runner.learn(...)` 进入训练循环

命令行参数解析在： [legged_gym/utils/helpers.py](legged_gym/utils/helpers.py) 的 `get_args()`。

**预留深入解读**：

- [ ] train.py 的参数覆盖优先级
- [ ] 多设备参数（`sim_device`/`rl_device`）含义

---

## 3.2 第 1 步：任务注册与配置装配

注册发生在： [legged_gym/envs/__init__.py](legged_gym/envs/__init__.py)

每个任务都绑定四元组：

- `task_name`
- `EnvClass`
- `EnvCfg`
- `TrainCfg`

例如 `a1` 任务绑定到：

- 环境类 `LeggedRobot`
- 环境配置 `A1RoughCfg`
- 训练配置 `A1RoughCfgPPO`

配置获取/覆写逻辑在： [legged_gym/utils/task_registry.py](legged_gym/utils/task_registry.py)

关键点：

- `get_cfgs()` 会把 `train_cfg.seed` 复制到 `env_cfg.seed`
- `update_cfg_from_args()` 会用 CLI 覆盖配置

**预留深入解读**：

- [ ] `task_registry` 的扩展方式（外部自定义任务）
- [ ] `seed` 传递路径

---

## 3.3 第 2 步：环境初始化（Isaac Gym 批量并行）

环境类主干： [legged_gym/envs/base/legged_robot.py](legged_gym/envs/base/legged_robot.py)

初始化流程：

1. `_parse_cfg()`：解析 `dt`、reward scales、命令范围、episode 长度
2. `BaseTask.__init__()`：创建 sim / viewer / 基础 buffer
3. `create_sim()`：创建地形、加载机器人资产、批量创建 `num_envs` 个环境
4. `_init_buffers()`：绑定 Isaac GPU Tensor（root state、dof、contact force）
5. `_prepare_reward_function()`：把非零奖励项映射到 `_reward_xxx()` 函数列表

地形生成由： [legged_gym/utils/terrain.py](legged_gym/utils/terrain.py)

**预留深入解读**：

- [ ] `_create_envs()` 中 URDF 资产与属性注入
- [ ] `terrain curriculum` 的地图组织方式

---

## 3.4 第 3 步：采样时每一步发生什么（环境 `step`）

在 [legged_gym/envs/base/legged_robot.py](legged_gym/envs/base/legged_robot.py) 的 `step()` 与 `post_physics_step()`：

1. 策略给出动作 `actions`
2. 动作裁剪后经 `_compute_torques()` 转成力矩（或目标位姿 PD）
3. 进行 `decimation` 次物理子步（控制频率低于仿真频率）
4. 刷新状态后：
   - `check_termination()` 判终止/超时
   - `compute_reward()` 累加奖励
   - `reset_idx(...)` 对终止环境重置
   - `compute_observations()` 生成新观测
5. 返回 `(obs, privileged_obs, reward, done, extras)`

说明：这正是 `VecEnv.step()` 约定接口（见 [../rsl_rl/rsl_rl/env/vec_env.py](../rsl_rl/rsl_rl/env/vec_env.py)）。

**预留深入解读**：

- [ ] `decimation` 与控制频率/仿真频率关系
- [ ] `extras["time_outs"]` 在 PPO 中的作用

###  `step()` 是整条“策略动作 → 物理推进 → 新观测/奖励”链路的入口。
位置在 [legged_robot.py**:79-103**](vscode-file://vscode-app/usr/share/code/resources/app/out/vs/code/electron-browser/workbench/workbench.html)。

按执行顺序拆解如下：

1. `clip_actions = self.cfg.normalization.clip_actions`
   `self.actions = torch.clip(actions, -clip_actions, clip_actions).to(self.device)`
   * 作用：把策略输出动作限制在安全范围，防止异常大动作导致仿真爆炸或梯度噪声过大。
   * RL 含义：相当于对策略输出加“硬约束”，提升训练稳定性与可迁移性。
   * 工程上：同时把张量放到仿真设备（GPU/CPU）上，避免后续设备不一致。
2. `self.render()`
   * 作用：更新可视化（若非 headless）。
   * 不影响奖励和动力学本身，主要用于调试和观察训练状态。
3. `for _ in range(self.cfg.control.decimation): ...`（控制降采样/动作重复）
   * 这段是核心： **一个 RL step 内做多次 physics substep** 。
   * 含义：策略频率低于物理频率。策略每给一次动作，该动作会保持若干小步去推进仿真。
   * 有效控制周期满足：dtcontrol=decimation×dtsim**d**t**control****=**d**ec**ima**t**i**o**n**×**d**t**sim****，在 [legged_robot.py**:456-463**](vscode-file://vscode-app/usr/share/code/resources/app/out/vs/code/electron-browser/workbench/workbench.html) 里也有对应设置。
4. `self.torques = self._compute_torques(self.actions)...`
   * 把高层动作映射为关节力矩（PD位置/速度控制或直接力矩），具体逻辑在 [legged_robot.py**:255-279**](vscode-file://vscode-app/usr/share/code/resources/app/out/vs/code/electron-browser/workbench/workbench.html)。
   * RL 含义：策略通常不直接学底层电机电流，而是学“更平滑、可控”的目标量，经控制器再变成物理可执行力矩。
5. `self.gym.set_dof_actuation_force_tensor(...)`
   * 把本步计算出的 batched 力矩写入 Isaac Gym。
   * 注意是并行 `num_envs` 一次性写入，吞吐高。
6. `self.gym.simulate(self.sim)`
   * 推进一小步物理仿真（积分器前进）。
7. `if self.device == 'cpu': self.gym.fetch_results(self.sim, True)`
   * CPU 路径下需要显式等待仿真完成并取回结果；GPU 路径通常走异步流水。
8. `self.gym.refresh_dof_state_tensor(self.sim)`
   * 刷新关节状态张量（位置/速度），给下一 substep 的控制器使用（如 PD 依赖当前 `dof_pos/dof_vel`）。
   * 这保证动作重复期间每个小步都基于最新物理状态闭环控制。
9. `self.post_physics_step()`
   * 这是“仿真后处理总管”，在 [legged_robot.py**:105-136**](vscode-file://vscode-app/usr/share/code/resources/app/out/vs/code/electron-browser/workbench/workbench.html)：
     * 刷新根状态、接触力；
     * 更新时间步计数；
     * `check_termination()` 判断终止；
     * `compute_reward()` 计算奖励；
     * `reset_idx()` 重置 done 的并行环境；
     * `compute_observations()` 生成新观测。
   * RL 含义：这里完成一次 MDP 转移所需的全部量：st+1,rt,donet**s**t**+**1****,**r**t,**d**o**n**e**t**。
10. 观测裁剪
    * `self.obs_buf = torch.clip(...)`，`privileged_obs_buf` 同理。
    * 作用：抑制异常值、降低分布长尾对策略网络和价值网络的冲击。
    * 常见于机器人任务，和 reward scaling 一样属于“数值稳定化手段”。
11. 返回五元组
    * `return self.obs_buf, self.privileged_obs_buf, self.rew_buf, self.reset_buf, self.extras`
    * 与上层 PPO runner 对接（`obs`, `privileged_obs`, `rewards`, `dones`, `infos`），对应你前面看的训练循环。

---

一句话总结：
`step()` 做的是“ **把策略动作在更高频物理世界里执行 decimation 次** ，然后统一产出 **新观测/奖励/终止标志** 给 PPO”，它就是环境侧 `VecEnv` 接口的核心实现。

---

## 3.5 第 4 步：Runner 组织采样与更新

主循环在： [../rsl_rl/rsl_rl/runners/on_policy_runner.py](../rsl_rl/rsl_rl/runners/on_policy_runner.py)

每个 iteration：

1. 采样阶段：循环 `num_steps_per_env`
   - `alg.act(...)`：策略采样动作 + 价值估计
   - `env.step(...)`
   - `alg.process_env_step(...)`：写入 rollout storage
2. 更新阶段：
   - `alg.compute_returns(...)`（GAE）
   - `alg.update()`（PPO 多 epoch、小批量优化）
3. 日志与保存：TensorBoard + `model_x.pt`

**预留深入解读**：

- [ ] runner 中 episode 统计与日志字段
- [ ] checkpoint 恢复逻辑

---

## 3.6 第 5 步：PPO 参数更新（核心强化学习过程）

实现文件： [../rsl_rl/rsl_rl/algorithms/ppo.py](../rsl_rl/rsl_rl/algorithms/ppo.py)

### 关键步骤

1. **行为策略采样**：
   - actor 输出均值，方差由可学习 `std` 给出
   - 采样动作 $a_t \sim \pi_\theta(a_t|s_t)$
2. **收集轨迹**：存入 [../rsl_rl/rsl_rl/storage/rollout_storage.py](../rsl_rl/rsl_rl/storage/rollout_storage.py)
3. **优势估计（GAE）**：
   - 使用 $\gamma$ 与 $\lambda$ 反向计算 returns/advantages
4. **PPO 剪切目标**：
   - 概率比 $r_t(\theta)=\frac{\pi_\theta(a_t|s_t)}{\pi_{\theta_{old}}(a_t|s_t)}$
   - 目标：$\min\big(r_tA_t,\ \text{clip}(r_t,1-\epsilon,1+\epsilon)A_t\big)$
5. **值函数损失 + 熵正则 + 梯度裁剪**：
   - 总损失 = surrogate + value loss - entropy bonus
6. **可选自适应学习率**：依据 KL 与 `desired_kl` 调整 lr

**预留深入解读**：

- [ ] PPO 剪切项在本项目中的具体数值影响
- [ ] `desired_kl` 自适应策略的稳定性分析

---

## 4. 配置体系（EnvCfg 与 TrainCfg）如何影响训练

核心定义： [legged_gym/envs/base/legged_robot_config.py](legged_gym/envs/base/legged_robot_config.py)

- `LeggedRobotCfg`：环境与仿真配置
  - `env/terrain/commands/init_state/control/asset/domain_rand/rewards/normalization/noise/sim`
- `LeggedRobotCfgPPO`：训练配置
  - `policy/algorithm/runner`

任务配置通过继承修改差异：

- [legged_gym/envs/a1/a1_config.py](legged_gym/envs/a1/a1_config.py)
- [legged_gym/envs/anymal_c/mixed_terrains/anymal_c_rough_config.py](legged_gym/envs/anymal_c/mixed_terrains/anymal_c_rough_config.py)
- [legged_gym/envs/anymal_c/flat/anymal_c_flat_config.py](legged_gym/envs/anymal_c/flat/anymal_c_flat_config.py)

### 一个非常关键的机制：奖励自动装配

`rewards.scales` 中非零项会自动对应到 `LeggedRobot` 的 `_reward_xxx()`。

例如：

- `tracking_lin_vel` -> `_reward_tracking_lin_vel()`
- `torques` -> `_reward_torques()`

这使得“奖励开关/调权重”主要靠配置，而不是改训练主循环。

**预留深入解读**：

- [ ] 各 reward 项的梯度信号强弱
- [ ] `only_positive_rewards` 对 early training 的影响

---

## 5. 观测、动作、奖励的语义（RL 视角）

### 5.1 状态/观测（Observation）

由 `compute_observations()` 拼接：

- 基座角速度
- 重力投影
- 速度命令
- 关节位置/速度
- 上一步动作
- （可选）地形高度采样

意义：

- 本体状态 + 任务条件（命令）+ 记忆痕迹（last action）
- 若加入高度测量，会提高崎岖地形可感知性

### 5.2 动作（Action）

策略输出连续动作（通常 $[-1,1]$ 附近高斯采样），再映射到：

- PD 目标位姿/速度，或
- 直接力矩（`control_type='T'`）

### 5.3 奖励（Reward）

本质是多目标加权和：

- 跟踪命令（前进/转向）
- 稳定性（姿态、垂向速度）
- 能耗/平滑（torque、action_rate）
- 安全约束（碰撞、关节极限）

可理解为：

$$
r_t = \sum_i w_i r_t^{(i)}
$$

其中权重 $w_i$ 来自配置。

---

## 6. 域随机化与课程学习在这里怎么落地

### 6.1 域随机化（Domain Randomization）

对应配置：`domain_rand`，落地代码在 `LeggedRobot`：

- 摩擦随机化：`_process_rigid_shape_props()`
- 机体质量随机化：`_process_rigid_body_props()`
- 随机推扰：`_push_robots()`

目标：让策略面对参数扰动，提高 sim-to-real 鲁棒性。

### 6.2 课程学习（Curriculum）

- 地形课程：`_update_terrain_curriculum()`
- 命令课程：`update_command_curriculum()`

目标：先学简单，再逐步提升难度，改善收敛稳定性。

---

## 7. Actor-Critic 网络结构与概率策略

网络文件： [../rsl_rl/rsl_rl/modules/actor_critic.py](../rsl_rl/rsl_rl/modules/actor_critic.py)

- Actor：MLP 输出动作均值
- Critic：MLP 输出状态价值 $V(s)$
- 动作分布：对角高斯 `Normal(mean, std)`，`std` 可学习

术语解释：

- **Actor-Critic**：一个网络（或两头）负责“做动作”，另一个负责“评估好坏”。
- **Entropy bonus**：鼓励探索，防止过早收敛到过窄分布。
- **GAE**：平衡方差与偏差的优势估计方法。

---

## 8. 训练产物、恢复与部署相关文件

- 模型保存（训练中）：`logs/<experiment>/<run>/model_x.pt`
- 推理脚本： [legged_gym/scripts/play.py](legged_gym/scripts/play.py)
- 导出：
  - JIT / ONNX 导出在 [legged_gym/utils/helpers.py](legged_gym/utils/helpers.py)
  - Sim2Sim（MuJoCo）脚本在 [legged_gym/scripts/sim2sim.py](legged_gym/scripts/sim2sim.py)

**预留深入解读**：

- [ ] `model_state_dict` 结构与加载路径
- [ ] ONNX 输入输出张量与部署侧接口约定

---

## 9. 文件关系图（文字版）

1. [legged_gym/scripts/train.py](legged_gym/scripts/train.py)-> 调 [legged_gym/utils/task_registry.py](legged_gym/utils/task_registry.py)
2. `task_registry.make_env()`-> 从 [legged_gym/envs/__init__.py](legged_gym/envs/__init__.py) 找任务注册-> 创建 [legged_gym/envs/base/legged_robot.py](legged_gym/envs/base/legged_robot.py)（或子类）
3. `task_registry.make_alg_runner()`-> 创建 [../rsl_rl/rsl_rl/runners/on_policy_runner.py](../rsl_rl/rsl_rl/runners/on_policy_runner.py)
4. Runner 内部
   -> 用 [../rsl_rl/rsl_rl/modules/actor_critic.py](../rsl_rl/rsl_rl/modules/actor_critic.py) 建网
   -> 用 [../rsl_rl/rsl_rl/algorithms/ppo.py](../rsl_rl/rsl_rl/algorithms/ppo.py) 更新
   -> 用 [../rsl_rl/rsl_rl/storage/rollout_storage.py](../rsl_rl/rsl_rl/storage/rollout_storage.py) 存轨迹

---

## 10. 重要名词速查（先给简版）

- **VecEnv**：并行环境接口，一次 step 同时推进大量子环境。
- **Rollout**：按当前策略采样的一段轨迹数据。
- **On-policy**：更新时只能使用“当前（或最近）策略”采样的数据。
- **PPO Clip**：限制策略更新幅度，防止性能崩塌。
- **Advantage ($A_t$)**：某动作相对基线价值的“超额收益”。
- **Return ($R_t$)**：从当前时刻开始的折扣累计回报。
- **Domain Randomization**：训练中随机化物理参数提升泛化。
- **Curriculum Learning**：逐步提高任务难度。
- **Privileged Observation**：仅给 critic 的额外信息（可选）。
- **Decimation**：每次策略动作对应多个物理仿真子步。

---

## 11. 后续可逐章补充的“占位目录”

1. 配置字段全解（`env/terrain/commands/...`）
2. `LeggedRobot.step()` 全流程逐行图解
3. 奖励项逐项推导与调参建议
4. PPO 数学细节与本工程默认超参数经验
5. 域随机化与 sim2real 经验总结
6. 模型导出（JIT/ONNX）与 sim2sim/real 接入流程

---

## 12. 你当前仓库中的一条建议（非必须）

你仓库里的 [legged_gym/envs/base/legged_robot_config.py](legged_gym/envs/base/legged_robot_config.py) 中 `num_observations` 被写成 `235 -187 -3`（结果为 45），这是可行的，但建议后续改为显式常量并在注释中同步观测组成，减少维护歧义。
