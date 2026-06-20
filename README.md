# Codex Claude Coop

中文 | [English](#english)

## 项目简介

`codex-claude-coop` 提供一个 Codex skill：`claude-worker-orchestrator`。

它的目标是把 Claude Code CLI 从“旁边手动聊天的工具”变成“Codex 可以调度、观察、审查、继续派活的开发 worker”。

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
  SKILL.md
  agents/openai.yaml
  references/protocol.md
  scripts/claude_worker_round.sh
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
Claude 写 claude_status.json / claude_result.md / changed_files.txt / claude_stdout.log
  ↓
Codex 读取结果并审查改动
  ↓
如果通过，结束
  ↓
如果不通过，Codex 写 next_task.md 并继续调度 Claude
```

## 标准 loop 目录

默认建议放在项目内：

```text
tmp/agent_loop/<任务名-时间>/
  current_task.md
  claude_status.json
  claude_result.md
  changed_files.txt
  claude_stdout.log
  codex_review.md
  next_task.md
```

## Claude worker 启动命令

在项目根目录执行：

```bash
~/.codex/skills/claude-worker-orchestrator/scripts/claude_worker_round.sh tmp/agent_loop/<loop-id>
```

脚本会读取：

```text
tmp/agent_loop/<loop-id>/current_task.md
```

并要求 Claude 写入：

```text
tmp/agent_loop/<loop-id>/claude_status.json
tmp/agent_loop/<loop-id>/claude_result.md
tmp/agent_loop/<loop-id>/changed_files.txt
tmp/agent_loop/<loop-id>/claude_stdout.log
```

## 右侧终端可见

如果你希望在右侧看到 Claude 工作，可以把上述命令粘贴到右侧终端运行。

Codex 仍然可以通过 loop 目录读取 Claude 产物并继续审查。

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

Example request:

```text
用 coop 技能工作: ask Claude to implement this feature, then have Codex review it and send follow-up tasks until it passes.
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

Or from the repository root:

```bash
mkdir -p ~/.codex/skills
rsync -a skills/claude-worker-orchestrator ~/.codex/skills/
```

Restart Codex or open a new Codex session so the skill can be discovered.

## Structure

```text
skills/claude-worker-orchestrator/
  SKILL.md
  agents/openai.yaml
  references/protocol.md
  scripts/claude_worker_round.sh
```

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
Claude writes claude_status.json / claude_result.md / changed_files.txt / claude_stdout.log
  ↓
Codex reviews the result and changed files
  ↓
If accepted, stop
  ↓
If not accepted, Codex writes next_task.md and dispatches Claude again
```

## Standard loop directory

Recommended project-local layout:

```text
tmp/agent_loop/<task-slug-timestamp>/
  current_task.md
  claude_status.json
  claude_result.md
  changed_files.txt
  claude_stdout.log
  codex_review.md
  next_task.md
```

## Launching a Claude worker round

From a project root:

```bash
~/.codex/skills/claude-worker-orchestrator/scripts/claude_worker_round.sh tmp/agent_loop/<loop-id>
```

The script reads:

```text
tmp/agent_loop/<loop-id>/current_task.md
```

and requires Claude to write:

```text
tmp/agent_loop/<loop-id>/claude_status.json
tmp/agent_loop/<loop-id>/claude_result.md
tmp/agent_loop/<loop-id>/changed_files.txt
tmp/agent_loop/<loop-id>/claude_stdout.log
```

## Visible terminal mode

If you want to watch Claude working, paste the launch command into the right-side terminal.

Codex can still monitor the loop directory, inspect artifacts, and continue the review-dispatch loop.

## Notes

- This skill does not replace Codex review. Claude's self-report is not enough.
- Codex should inspect changed files, status JSON, logs, and relevant validation output.
- Each Claude worker round should exit after completion instead of staying in an open-ended interactive prompt.
- Network, auth, or permission failures should be treated as environment issues, not project-code results.
