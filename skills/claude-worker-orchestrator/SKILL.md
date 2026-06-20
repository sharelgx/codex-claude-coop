---
name: claude-worker-orchestrator
description: "Use when the user wants Codex to orchestrate Claude Code CLI as a visible development worker: dispatch coding tasks to Claude, let the user watch Claude working in a terminal, read Claude's status/log/result files, review changed files, run targeted validation when appropriate, write the next task, and repeat a Codex review to Claude worker loop until the project task is complete or blocked. Primary trigger phrase: 用 coop 技能工作. Also trigger on requests such as 调度Claude开发, 让Claude干活我来/你来检查, Claude完成后你接手, 多Agent闭环, 右侧看Claude工作, 自动派任务给Claude, or building a Codex-Claude development loop."
---

# Claude Worker Orchestrator

## Goal

Turn Claude Code CLI into a supervised worker, not a free-form side chat. Codex remains the coordinator: define the task, launch or instruct the launch, read artifacts, review results, and issue the next round.

## Required stance

- Treat user-facing communication and generated task docs as Chinese by default.
- Keep Codex as the final reviewer and owner of the loop.
- Do not rely on Claude's self-report alone. Inspect files, logs, status JSON, and relevant outputs.
- Prefer one-shot Claude worker rounds that exit after writing status/result files.
- Do not let Claude run as an indefinite interactive chat unless the user explicitly wants manual operation.
- If the user wants to watch Claude, make the Claude command visible in a terminal and also tee output to a log file.

## Loop directory

Use `tmp/agent_loop/<slug>-<timestamp>/` inside the active project unless the user specifies another location.

Read `references/protocol.md` before starting a new loop or diagnosing an existing loop.

## Available scripts

| Script | Purpose |
|--------|---------|
| `scripts/claude_worker_round.sh <loop-dir> [--timeout N] [--proxy] [--dry-run]` | Launch one Claude worker round |
| `scripts/coop_status.sh <loop-dir>` | Print comprehensive loop status report |
| `scripts/coop_prepare_round.sh <slug> [project-root]` | Initialize a new loop directory with task template |
| `scripts/coop_watch.sh <loop-dir>` | Real-time loop monitoring (5s refresh) |

## Standard workflow

1. Create a loop directory:
   ```bash
   /Users/liulaoshi/.codex/skills/claude-worker-orchestrator/scripts/coop_prepare_round.sh <task-slug>
   ```

2. Write `current_task.md` with a precise Chinese task for Claude.

3. Require Claude to write `claude_status.json`, `claude_result.md`, and `changed_files.txt` before exiting.

4. Launch Claude with the worker script. Two modes:

   **A. Background mode** — Codex runs it directly:
   ```bash
   /Users/liulaoshi/.codex/skills/claude-worker-orchestrator/scripts/claude_worker_round.sh <loop-dir>
   ```

   **B. Right-side visible mode** (recommended) — Codex generates the command, user pastes it in the right terminal:
   ```bash
   # Tell the user to run this in their right-side terminal:
   /Users/liulaoshi/.codex/skills/claude-worker-orchestrator/scripts/claude_worker_round.sh <loop-dir>
   ```

5. Monitor progress using:
   ```bash
   /Users/liulaoshi/.codex/skills/claude-worker-orchestrator/scripts/coop_status.sh <loop-dir>
   ```
   or in another terminal:
   ```bash
   /Users/liulaoshi/.codex/skills/claude-worker-orchestrator/scripts/coop_watch.sh <loop-dir>
   ```

6. Watch for completion by checking `claude_status.json` (status becomes `done`/`failed`/`blocked`).

7. Review the implementation: read changed files and relevant reports.

8. Run only targeted validation that is necessary for the task or explicitly requested.

9. Write `codex_review.md`.

10. If issues remain, write `next_task.md`, promote it to `current_task.md`, and start another Claude round.

11. Stop only when acceptance criteria pass or when the blocker is concrete and needs user/external action.

## Claude task requirements

Every Claude task must include these requirements:

```text
你是 Claude Code worker，本轮只做 current_task.md 中定义的工作。
请直接修改项目文件，不要停在开放式讨论。
完成后必须写入：
1. claude_status.json：status 为 done / blocked / failed，包含 changedFiles、commandsRun、remainingIssues。
2. claude_result.md：中文总结，说明做了什么、如何验证、还有什么风险。
3. changed_files.txt：每行一个改动文件路径。
完成后退出，不要继续等待人工输入。
```

## Completion criteria

A Claude round is not complete just because the terminal printed a success sentence. It is complete only when:

- `claude_status.json` exists and status is `done`, `blocked`, or `failed`.
- `claude_result.md` exists.
- `changed_files.txt` exists, even if empty.
- The Claude worker process for this round has exited.

The worker script has a **status fallback mechanism**: if Claude exits but status is still `running`, the script automatically writes `failed` (or `done` if exit code was 0).

## Review policy

- If Claude changed code, inspect the changed files before trusting it.
- If Claude generated a report, inspect the report source enough to confirm it is real and relevant.
- If Claude claims validation passed, prefer checking the saved command output or rerunning a narrow validation only when needed.
- If Claude introduces broad unrelated changes, stop and ask the user before proceeding.

## Right-side visibility

If the user wants to watch Claude in the right-side terminal, give them the exact command to paste:

```bash
/Users/liulaoshi/.codex/skills/claude-worker-orchestrator/scripts/claude_worker_round.sh tmp/agent_loop/<loop-id>
```

Codex can then monitor the loop directory via `coop_status.sh` or by reading the files directly.

## Failure handling

- **Network/auth error**: summarize exact error, do not rewrite project code to work around provider login failures. Consider `--proxy` flag.
- **Permission prompt**: explain which command caused it and whether it can be avoided.
- **Claude partial work**: review partial changed files, write a smaller next task, and rerun.
- **Ambiguous task**: Codex should narrow the task before dispatching Claude.
- **Timeout**: default 1800s (30 min). Use `--timeout` for longer tasks. Script auto-writes `failed` on timeout.
- **No output**: `claude -p` may buffer internally. Check if process is alive and log file is growing. Consider using `coop_watch.sh` in another terminal.
- **Status stuck at running**: if Claude process exited, the script should have auto-fixed it. If the script was killed externally, manually update `claude_status.json`.
