# Codex-Claude Worker Loop Protocol

## Directory layout

Create one loop directory per user request:

```text
tmp/agent_loop/<slug>-<timestamp>/
  current_task.md
  claude_status.json
  claude_result.md
  changed_files.txt
  claude_stdout.log
  codex_review.md
  next_task.md
  rounds/
```

## `current_task.md`

Chinese task file written by Codex. It should include:

- 背景
- 本轮目标
- 必须修改/禁止修改的范围
- 验收标准
- 必须产出的文件
- 完成后退出的要求

## `claude_status.json`

Expected schema:

```json
{
  "status": "done",
  "summary": "中文一句话总结",
  "changedFiles": ["path/to/file"],
  "commandsRun": ["command ..."],
  "validation": [
    {"command": "...", "result": "passed|failed|skipped", "note": "..."}
  ],
  "remainingIssues": [],
  "blockedReason": null
}
```

Allowed status values:

- `done`: Claude believes the round is complete.
- `blocked`: external/user/environment blocker.
- `failed`: Claude attempted but failed.

## `codex_review.md`

Written by Codex after review. Include:

- 本轮结论：pass / needs_next_round / blocked
- 已确认事实
- 发现的问题
- 是否需要下一轮 Claude
- 下一轮任务摘要

## Round loop

1. Codex writes `current_task.md`.
2. Claude runs one round and exits.
3. Codex checks status/result/changed files.
4. Codex reviews implementation and validation evidence.
5. If pass, report to user.
6. If not pass, Codex writes `next_task.md` and starts another round.

## Recommended Claude launch command

From the project root:

```bash
/Users/liulaoshi/.codex/skills/claude-worker-orchestrator/scripts/claude_worker_round.sh tmp/agent_loop/<loop-id>
```

The script tees stdout/stderr to `claude_stdout.log` so the user can watch and Codex can inspect later.
