# WeChat Post Draft

## Title

CC Swarm: 用 3200 行 Bash 实现 Claude Code 多智能体协调

## Body

我同时在一台 MacBook Pro 上运行 25 个 Claude Code agent, 每个 agent 独立拥有 200k token 上下文窗口, 可以互相派发任务、交叉代码审查、合并分支。

这套系统叫 CC Swarm -- 一个纯 Bash 实现的 peer-mesh 多智能体协调框架, 作为 Claude Code 的 plugin 运行在 tmux 之上。

### 核心特性

- **任务生命周期**: 创建、派发、追踪、更新、收集, 全部基于结构化 JSON 信封
- **绑定式代码审查**: ACCEPT/REVISE/REJECT 三种裁决, 自动递增轮次, 审查是门禁而非建议
- **监控 Agent**: 专职看门狗, 检测空闲/卡死/权限阻塞, 自动提醒或升级处理
- **DAG 工作流**: JSON 声明任务依赖, 自动调度跨 agent 并行执行
- **广播**: `swarm broadcast "更新日志..."` 一键通知所有空闲 agent
- **合并协调器**: `git merge-tree` 冲突检测, 安全顺序合并

### 对比

| | CC Swarm | OMC | Claude Squad | Gas Town |
|---|---|---|---|---|
| 语言 | Bash | TypeScript | Go | Go |
| 代码量 | ~3,200 行 | ~182k 行 | ~6k 行 | ~12k+ 行 |
| 架构 | Peer mesh | Hub-spoke | Session manager | Worktree manager |
| 审查协议 | 绑定裁决 | 无 | 无 | 无 |
| 任务生命周期 | 完整 | Pipeline | 无 | 无 |
| 测试 | 190 | -- | -- | -- |

### 设计哲学

**Peer mesh, not hub-spoke.**
没有中心调度器, 每个 agent 平等通信, 任何 agent 可以向任何其他 agent 派发任务。

**Stateless CLI, stateful filesystem.**
`swarm` 二进制读写 `~/.claude-swarm/` 后退出。没有 daemon, 没有 sidecar。状态是纯 JSON 文件 -- 用 `cat` 和 `jq` 即可调试。

**~3,200 行 Bash, 零额外依赖。**
不需要 npm, 不需要 TypeScript runtime, 不需要 Docker。依赖: bash + tmux + jq。

GitHub: github.com/x-zheng16/cc-swarm
