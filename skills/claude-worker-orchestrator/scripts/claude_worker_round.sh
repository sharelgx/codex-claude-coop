#!/usr/bin/env bash
set -euo pipefail

LOOP_DIR="${1:-}"
if [[ -z "$LOOP_DIR" ]]; then
  echo "Usage: $0 <loop-dir>" >&2
  exit 2
fi

mkdir -p "$LOOP_DIR"
TASK_FILE="$LOOP_DIR/current_task.md"
STATUS_FILE="$LOOP_DIR/claude_status.json"
LOG_FILE="$LOOP_DIR/claude_stdout.log"

if [[ ! -f "$TASK_FILE" ]]; then
  echo "Missing task file: $TASK_FILE" >&2
  exit 2
fi

cat > "$STATUS_FILE" <<JSON
{
  "status": "running",
  "summary": "Claude worker started",
  "changedFiles": [],
  "commandsRun": [],
  "validation": [],
  "remainingIssues": [],
  "blockedReason": null
}
JSON

PROMPT="$(cat "$TASK_FILE")

请严格按任务文件执行。完成后必须写入：
- $STATUS_FILE
- $LOOP_DIR/claude_result.md
- $LOOP_DIR/changed_files.txt

写完后退出，不要继续等待人工输入。"

{
  echo "[claude-worker] loop_dir=$LOOP_DIR"
  echo "[claude-worker] started_at=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "[claude-worker] task_file=$TASK_FILE"
  echo "[claude-worker] ------------------------------------------------------------"
  claude --dangerously-skip-permissions -p "$PROMPT"
  echo "[claude-worker] ------------------------------------------------------------"
  echo "[claude-worker] exited_at=$(date '+%Y-%m-%d %H:%M:%S')"
} 2>&1 | tee -a "$LOG_FILE"
