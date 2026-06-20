# Codex-Claude Worker Loop 协议

## 目录结构

每个用户请求创建一个 loop 目录：

```text
tmp/agent_loop/<slug>-<timestamp>/
  current_task.md          # Codex 写给 Claude 的当前任务
  claude_status.json       # Claude/脚本 写状态
  claude_result.md         # Claude 写中文总结
  changed_files.txt        # Claude 写改动文件列表
  claude_stdout.log        # stdout/stderr 实时日志
  claude_worker.pid        # worker 进程 PID（运行中）
  codex_review.md          # Codex 审查结论
  next_task.md             # Codex 写下一轮任务
```

## `current_task.md`

中文任务文件，由 Codex 编写。必须包含：

- 背景
- 本轮目标
- 必须修改 / 禁止修改的范围
- 验收标准
- 必须产出的文件
- 完成后退出的要求

## `claude_status.json`

### 结构

```json
{
  "status": "done",
  "summary": "中文一句话总结",
  "startedAt": "2026-06-20T02:00:00Z",
  "finishedAt": "2026-06-20T02:15:00Z",
  "exitCode": 0,
  "changedFiles": ["path/to/file"],
  "commandsRun": ["command ..."],
  "validation": [
    {"command": "...", "result": "passed|failed|skipped", "note": "..."}
  ],
  "remainingIssues": [],
  "blockedReason": null
}
```

### 状态值

| 状态 | 含义 |
|------|------|
| `done` | Claude 认为本轮完成 |
| `blocked` | 外部环境/用户/权限阻塞 |
| `failed` | Claude 尝试了但失败 |
| `running` | worker 正在执行（初始状态） |

### 状态兜底规则

**重要**：如果 Claude 进程退出但 `claude_status.json` 仍为 `running`，`claude_worker_round.sh` 脚本会自动兜底：

- 退出码 0 → 标记为 `done`（附注"脚本兜底"）
- 退出码 124（超时）→ 标记为 `failed`，blockedReason 写超时
- 其他退出码 → 标记为 `failed`，blockedReason 写退出码

脚本还会自动补充 `startedAt`、`finishedAt`、`exitCode` 字段。

## `codex_review.md`

由 Codex 审查后编写，包含：

- 本轮结论：pass / needs_next_round / blocked
- 已确认事实
- 发现的问题
- 是否需要下一轮 Claude
- 下一轮任务摘要

## 循环流程

```text
1. Codex 写 current_task.md
2. 启动 Claude worker（后台或右侧终端）
3. Claude 执行任务、写出产物文件、退出
4. Codex 检查 status/result/changed files
5. Codex 审查实现和验证结果
6. 如果通过 → 报告用户
7. 如果不通过 → Codex 写 next_task.md，开始下一轮
```

## 工作模式

### A. 后台模式

Codex 直接启动 worker，用户不看实时输出。

```bash
/Users/liulaoshi/.codex/skills/claude-worker-orchestrator/scripts/claude_worker_round.sh tmp/agent_loop/<loop-id>
```

**优点**：全自动，不需要人工介入。
**缺点**：用户右侧终端看不到 Claude 工作过程。

### B. 右侧可见模式（推荐）

Codex 生成命令，用户在右侧终端粘贴运行。

```bash
# 用户在右侧终端执行：
/Users/liulaoshi/.codex/skills/claude-worker-orchestrator/scripts/claude_worker_round.sh tmp/agent_loop/<loop-id>
```

**优点**：用户可实时看到 Claude 输出。
**缺点**：需要用户手动粘贴命令启动。

### C. Watch 监控模式

在另一个终端运行 watch 脚本，每 5 秒刷新状态：

```bash
/Users/liulaoshi/.codex/skills/claude-worker-orchestrator/scripts/coop_watch.sh tmp/agent_loop/<loop-id>
```

## 脚本工具

| 脚本 | 用途 |
|------|------|
| `scripts/claude_worker_round.sh <loop-dir> [--timeout N] [--proxy] [--dry-run]` | 启动一轮 Claude worker |
| `scripts/coop_status.sh <loop-dir>` | 检查 loop 状态报告 |
| `scripts/coop_prepare_round.sh <slug> [project-root]` | 初始化新 loop 目录 |
| `scripts/coop_watch.sh <loop-dir>` | 实时监控 loop 目录 |

### claude_worker_round.sh 参数

| 参数 | 说明 |
|------|------|
| `<loop-dir>` | loop 目录路径（必须） |
| `--timeout N` | 超时秒数，默认 1800（30 分钟） |
| `--proxy` | 注入 HTTP/HTTPS/SOCKS 代理 |
| `--dry-run` | 只验证文件协议，不实际调用 Claude |

## 故障处理

### Claude 长时间无输出

1. 检查 claude 进程是否存在：`pgrep -f "claude.*dangerously-skip-permissions"`
2. 检查日志文件是否有增长：`ls -la <loop-dir>/claude_stdout.log`
3. Claude CLI `-p` 模式可能有内部缓冲，stdout 不会实时 flush
4. 如果确认卡住，可以 kill 进程，脚本会自动写 failed 状态

### 网络/代理问题

启动时加 `--proxy` 参数注入代理环境变量：

```bash
claude_worker_round.sh <loop-dir> --proxy
```

或手动设置：

```bash
export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890
export ALL_PROXY=socks5h://127.0.0.1:7891
```

### status 一直是 running

- 如果 Claude 进程还在运行 → 等待或检查日志
- 如果 Claude 进程已退出 → 脚本应已自动兜底写 failed
- 如果脚本也异常退出（如被 kill -9） → 手动更新 `claude_status.json`

### Claude 权限提示 (permission prompt)

使用 `--dangerously-skip-permissions` 可跳过所有权限检查。仅在可信环境下使用。

### 超时

默认 30 分钟超时。对于大任务可增加：

```bash
claude_worker_round.sh <loop-dir> --timeout 3600
```

超时后脚本自动写：

```json
{
  "status": "failed",
  "blockedReason": "claude worker timeout after 3600s"
}
```
