# Codex Claude Coop

中文 | [English](#english)

## 项目简介

`codex-claude-coop` 提供一个 Codex skill：`claude-worker-orchestrator`。

它的目标是把 Claude Code CLI 从"旁边手动聊天的工具"变成"Codex 可以调度、观察、审查、继续派活的开发 worker"。

推荐触发语：

```text
用 coop 技能工作
```

典型使用方式：

```text
用 coop 技能工作：让 Claude 开发这个功能，完成后你检查，如果不通过继续给 Claude 派下一轮任务。
```

## 能解决什么问题

当项目较大时，你可能希望：

- 你只和 Codex 沟通需求。
- Codex 把开发任务拆给 Claude Code CLI。
- 你能在右侧终端看到 Claude 正在工作。
- Claude 完成后写入状态、日志、结果和改动文件。
- Codex 接手检查、回归、判断是否通过。
- 如果没通过，Codex 自动生成下一轮 Claude 任务。
- 多轮循环直到完成或明确 blocked。

## 安装

把本仓库中的 skill 复制到 Codex skills 目录：

```bash
mkdir -p ~/.codex/skills
cp -R skills/claude-worker-orchestrator ~/.codex/skills/
```

或者从仓库根目录执行：

```bash
mkdir -p ~/.codex/skills
rsync -a skills/claude-worker-orchestrator ~/.codex/skills/
```

安装后重启 Codex，或开启新的 Codex 会话，让 skill 被重新发现。

## 目录结构

```text
skills/claude-worker-orchestrator/
  SKILL.md                              # skill 定义（触发语、工作流）
  agents/openai.yaml                    # agent 显示配置
  references/protocol.md                # loop 协议文档
  scripts/
    claude_worker_round.sh              # 启动一轮 Claude worker
    coop_status.sh                      # 检查 loop 状态
    coop_prepare_round.sh               # 初始化 loop 目录
    coop_watch.sh                       # 实时监控 loop 目录
```

## 核心工作流

```text
用户提出需求
  ↓
Codex 写 current_task.md
  ↓
Claude Code CLI 作为 worker 执行任务
  ↓
用户可以在右侧终端观察 Claude 输出
  ↓
Claude 写 claude_status.json / claude_result.md / changed_files.txt
  ↓
脚本自动记录 claude_stdout.log / startedAt / finishedAt / exitCode
  ↓
Codex 读取结果并审查改动
  ↓
如果通过，结束
  ↓
如果不通过，Codex 写 next_task.md 并继续调度 Claude
```

## 脚本工具

### 初始化 loop 目录

```bash
~/.codex/skills/claude-worker-orchestrator/scripts/coop_prepare_round.sh <任务名> [项目根目录]
# 示例：
~/.codex/skills/claude-worker-orchestrator/scripts/coop_prepare_round.sh fix-q7-image /path/to/project
```

### 启动 Claude worker

```bash
~/.codex/skills/claude-worker-orchestrator/scripts/claude_worker_round.sh <loop-dir> [--timeout 1800] [--proxy] [--dry-run]
```

参数说明：

| 参数 | 说明 |
|------|------|
| `<loop-dir>` | loop 目录路径（必须） |
| `--timeout N` | 超时秒数，默认 1800（30 分钟） |
| `--proxy` | 注入 HTTP/HTTPS/SOCKS 代理 |
| `--dry-run` | 只验证文件协议，不实际调用 Claude |

改进要点：
- **任务通过 stdin 传入 Claude**，不再塞进 `-p` 命令行参数（避免 `ps` 污染）
- **自动捕获退出码**，记录 `startedAt` / `finishedAt` / `exitCode`
- **状态兜底**：如果 Claude 退出但 `claude_status.json` 仍是 `running`，脚本自动写 `failed`
- **可选超时**：超时后自动终止并写入超时状态
- **可选代理注入**

### 检查 loop 状态

```bash
~/.codex/skills/claude-worker-orchestrator/scripts/coop_status.sh <loop-dir>
```

输出包含：
- `claude_status.json` 全字段摘要
- 产物文件是否存在
- Claude worker 进程是否在运行
- 最近 10 分钟修改过的文件
- 日志最后 40 行

### 实时监控

```bash
~/.codex/skills/claude-worker-orchestrator/scripts/coop_watch.sh <loop-dir>
```

每 5 秒刷新，显示状态、进程、产物、日志增量。worker 结束后自动退出。

## 标准 loop 目录

默认建议放在项目内：

```text
tmp/agent_loop/<任务名-时间>/
  current_task.md          # Codex 写给 Claude 的当前任务
  claude_status.json       # Claude/脚本 写状态（含 startedAt/finishedAt/exitCode）
  claude_result.md         # Claude 写中文总结
  changed_files.txt        # Claude 写改动文件列表
  claude_stdout.log        # stdout/stderr 实时日志
  claude_worker.pid        # worker 进程 PID（运行期间存在）
  codex_review.md          # Codex 审查结论
  next_task.md             # Codex 写下一轮任务
```

## 工作模式

### A. 后台模式

Codex 直接启动 worker，用户不看实时输出。

**优点**：全自动。**缺点**：用户看不到 Claude 工作过程。

### B. 右侧可见模式（推荐）

Codex 生成命令，用户在右侧终端粘贴运行。

**优点**：用户可实时看到 Claude 输出。**缺点**：需要手动粘贴。

### C. Watch 监控模式

在另一个终端运行 `coop_watch.sh`，每 5 秒刷新状态和日志增量。

## Troubleshooting

### Claude 长时间无输出

1. 确认进程是否存在：`pgrep -f "claude.*dangerously-skip-permissions"`
2. 查看日志是否增长：`ls -la <loop-dir>/claude_stdout.log`
3. Claude CLI `-p` 模式有内部缓冲，stdout 不会实时 flush
4. 如果确认卡住，kill 进程后脚本会自动写 `failed` 状态

### 网络代理

启动时加 `--proxy`：

```bash
claude_worker_round.sh <loop-dir> --proxy
```

默认注入：

```text
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
ALL_PROXY=socks5h://127.0.0.1:7891
```

### status 一直是 running

- Claude 进程还在 → 等待或检查日志
- Claude 进程已退出 → 脚本已自动兜底写 `failed`
- 脚本也被异常 kill → 手动更新 `claude_status.json`

### Cookie/权限问题

使用 `--dangerously-skip-permissions` 可跳过权限检查。仅在可信环境下使用。

## 注意事项

- 这个 skill 不替代 Codex 审查。Claude 的自报成功不能直接信任。
- Codex 应检查改动文件、状态 JSON、日志和必要的回归结果。
- Claude worker 每轮应该完成后退出，不要长期停在交互式等待状态。
- 如果 Claude 网络、登录或权限失败，应先解决环境问题，不要把环境错误误判为项目代码问题。

---

# English

## Overview

`codex-claude-coop` provides a Codex skill named `claude-worker-orchestrator`.

Its purpose is to turn Claude Code CLI from a manually operated side chat into a visible, supervised development worker that Codex can dispatch, monitor, review, and re-dispatch.

Recommended trigger phrase:

```text
用 coop 技能工作
```

## What it helps with

For larger projects, this workflow lets you:

- Talk to Codex as the main coordinator.
- Let Codex write a precise task for Claude Code CLI.
- Watch Claude working in a terminal.
- Require Claude to write status, logs, results, and changed-file lists.
- Let Codex review the implementation and validation evidence.
- Let Codex create the next Claude task when the result is not good enough.
- Repeat until the task passes or a concrete blocker is found.

## Installation

Copy the skill into your Codex skills directory:

```bash
mkdir -p ~/.codex/skills
cp -R skills/claude-worker-orchestrator ~/.codex/skills/
```

Restart Codex or open a new session so the skill can be discovered.

## Structure

```text
skills/claude-worker-orchestrator/
  SKILL.md                              # Skill definition (triggers, workflow)
  agents/openai.yaml                    # Agent display config
  references/protocol.md                # Loop protocol documentation
  scripts/
    claude_worker_round.sh              # Launch one Claude worker round
    coop_status.sh                      # Check loop status
    coop_prepare_round.sh               # Initialize loop directory
    coop_watch.sh                       # Real-time loop monitoring
```

## Scripts

### Initialize a loop directory

```bash
~/.codex/skills/claude-worker-orchestrator/scripts/coop_prepare_round.sh <task-slug> [project-root]
```

### Launch a Claude worker round

```bash
~/.codex/skills/claude-worker-orchestrator/scripts/claude_worker_round.sh <loop-dir> [--timeout 1800] [--proxy] [--dry-run]
```

| Flag | Description |
|------|-------------|
| `<loop-dir>` | Loop directory path (required) |
| `--timeout N` | Timeout in seconds, default 1800 (30 min) |
| `--proxy` | Inject HTTP/HTTPS/SOCKS proxy env vars |
| `--dry-run` | Validate file protocol only, don't call Claude |

Key improvements:
- **Task passed via stdin** instead of `-p` command-line arg (avoids `ps` pollution)
- **Exit code capture** with `startedAt` / `finishedAt` / `exitCode` in status JSON
- **Status fallback**: if Claude exits but status is still `running`, script auto-writes `failed`
- **Optional timeout**: auto-terminates and writes timeout status
- **Optional proxy injection**

### Check loop status

```bash
~/.codex/skills/claude-worker-orchestrator/scripts/coop_status.sh <loop-dir>
```

### Real-time monitoring

```bash
~/.codex/skills/claude-worker-orchestrator/scripts/coop_watch.sh <loop-dir>
```

Refreshes every 5 seconds. Auto-exits when the worker finishes.

## Workflow

```text
User describes the task
  ↓
Codex writes current_task.md
  ↓
Claude Code CLI runs as a worker
  ↓
The user can watch Claude output in a terminal
  ↓
Claude writes claude_status.json / claude_result.md / changed_files.txt
  ↓
Script records claude_stdout.log / startedAt / finishedAt / exitCode
  ↓
Codex reviews the result and changed files
  ↓
If accepted, stop
  ↓
If not accepted, Codex writes next_task.md and dispatches Claude again
```

## Work Modes

### A. Background mode

Codex launches the worker directly. User doesn't see real-time output.

### B. Right-side visible mode (recommended)

Codex generates the command. User pastes it into the right-side terminal.

### C. Watch mode

Run `coop_watch.sh` in another terminal for periodic status and log updates.

## Troubleshooting

- **No output from Claude**: CLI `-p` mode has internal buffering. Check if the process is alive and the log file is growing.
- **Network proxy**: Use `--proxy` flag or set `HTTP_PROXY`/`HTTPS_PROXY`/`ALL_PROXY` manually.
- **Status stuck at running**: If Claude process exited, the script should have auto-fixed it. If the script was killed externally, update `claude_status.json` manually.
- **Timeout**: Default 30 min. Use `--timeout` for longer tasks. Script writes `failed` on timeout.

## Notes

- This skill does not replace Codex review. Claude's self-report is not enough.
- Codex should inspect changed files, status JSON, logs, and relevant validation output.
- Each Claude worker round should exit after completion.
- Network, auth, or permission failures are environment issues, not project-code results.
