#!/usr/bin/env bash
# claude_worker_round.sh — 启动一轮 Claude Code CLI worker
# 用法: claude_worker_round.sh <loop-dir> [--timeout SECONDS] [--proxy] [--dry-run]
#
# 改进点:
#   - 任务通过 stdin 传入 Claude，不再塞进命令行参数（避免 ps 污染）
#   - 捕获 Claude 退出码
#   - 如果 Claude 退出但 claude_status.json 仍是 running，自动写 failed
#   - 记录 startedAt / finishedAt / exitCode
#   - 可选 timeout（默认 1800 秒）
#   - 可选 proxy 注入
#   - --dry-run 模式只验证文件协议不真实调用 Claude

set -uo pipefail

# ── 参数解析 ──────────────────────────────────────────────
LOOP_DIR=""
TIMEOUT=1800
USE_PROXY=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --proxy)
      USE_PROXY=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -*)
      echo "[claude-worker] 未知参数: $1" >&2
      exit 2
      ;;
    *)
      if [[ -z "$LOOP_DIR" ]]; then
        LOOP_DIR="$1"
      else
        echo "[claude-worker] 多余参数: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [[ -z "$LOOP_DIR" ]]; then
  echo "用法: $0 <loop-dir> [--timeout SECONDS] [--proxy] [--dry-run]" >&2
  exit 2
fi

# ── 路径定义 ──────────────────────────────────────────────
mkdir -p "$LOOP_DIR"
TASK_FILE="$LOOP_DIR/current_task.md"
STATUS_FILE="$LOOP_DIR/claude_status.json"
RESULT_FILE="$LOOP_DIR/claude_result.md"
CHANGED_FILE="$LOOP_DIR/changed_files.txt"
LOG_FILE="$LOOP_DIR/claude_stdout.log"
PID_FILE="$LOOP_DIR/claude_worker.pid"

if [[ ! -f "$TASK_FILE" ]]; then
  echo "[claude-worker] ❌ 缺少任务文件: $TASK_FILE" >&2
  exit 2
fi

# ── 时间记录 ──────────────────────────────────────────────
STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# ── 写入初始状态 ──────────────────────────────────────────
cat > "$STATUS_FILE" <<JSON
{
  "status": "running",
  "summary": "Claude worker 已启动",
  "startedAt": "$STARTED_AT",
  "finishedAt": null,
  "exitCode": null,
  "changedFiles": [],
  "commandsRun": [],
  "validation": [],
  "remainingIssues": [],
  "blockedReason": null
}
JSON

# ── 构建 prompt（不塞进命令行参数） ───────────────────────
TASK_CONTENT="$(cat "$TASK_FILE")"
PROMPT="$TASK_CONTENT

---

请严格按上述任务执行。完成后必须在 loop 目录写入以下文件:
1. $STATUS_FILE — claude_status.json，status 为 done/blocked/failed，包含 changedFiles、commandsRun、remainingIssues。
2. $RESULT_FILE — claude_result.md，中文总结。
3. $CHANGED_FILE — changed_files.txt，每行一个改动文件路径。

写完后退出，不要继续等待人工输入。"

# ── 代理注入 ──────────────────────────────────────────────
if $USE_PROXY; then
  export HTTP_PROXY="${HTTP_PROXY:-http://127.0.0.1:7890}"
  export HTTPS_PROXY="${HTTPS_PROXY:-http://127.0.0.1:7890}"
  export ALL_PROXY="${ALL_PROXY:-socks5h://127.0.0.1:7891}"
  export NO_PROXY="${NO_PROXY:-localhost,127.0.0.1,::1}"
  echo "[claude-worker] 🌐 代理已注入: HTTP_PROXY=$HTTP_PROXY"
fi

# ── 日志 header ───────────────────────────────────────────
{
  echo "================================================================"
  echo "[claude-worker] loop_dir=$LOOP_DIR"
  echo "[claude-worker] started_at=$STARTED_AT"
  echo "[claude-worker] timeout=${TIMEOUT}s"
  echo "[claude-worker] task_file=$TASK_FILE"
  echo "[claude-worker] dry_run=$DRY_RUN"
  echo "================================================================"
} | tee -a "$LOG_FILE"

# ── dry-run 模式 ─────────────────────────────────────────
if $DRY_RUN; then
  echo "[claude-worker] 🧪 dry-run 模式，跳过实际 Claude 调用" | tee -a "$LOG_FILE"
  echo "[claude-worker] ✅ 任务文件存在且可读 ($(wc -c < "$TASK_FILE") bytes)" | tee -a "$LOG_FILE"
  echo "[claude-worker] ✅ 状态文件已初始化" | tee -a "$LOG_FILE"
  echo "[claude-worker] ✅ 日志文件就绪" | tee -a "$LOG_FILE"

  FINISHED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  cat > "$STATUS_FILE" <<JSON
{
  "status": "done",
  "summary": "dry-run 模式完成，文件协议验证通过",
  "startedAt": "$STARTED_AT",
  "finishedAt": "$FINISHED_AT",
  "exitCode": 0,
  "changedFiles": [],
  "commandsRun": [],
  "validation": [{"command": "dry-run", "result": "passed", "note": "文件协议验证通过"}],
  "remainingIssues": [],
  "blockedReason": null
}
JSON
  echo "dry-run 完成，文件协议验证通过。" > "$RESULT_FILE"
  touch "$CHANGED_FILE"
  echo "[claude-worker] 🏁 dry-run 结束" | tee -a "$LOG_FILE"
  exit 0
fi

# ── 启动 Claude（通过 stdin 传入 prompt） ─────────────────
# 使用 timeout 命令（macOS 需要 brew install coreutils 的 gtimeout，或 perl 替代）
_run_claude() {
  echo "$PROMPT" | claude --dangerously-skip-permissions -p 2>&1 | tee -a "$LOG_FILE"
}

# 记录 PID 以供外部监控
EXIT_CODE=0

if command -v gtimeout &>/dev/null; then
  # macOS with coreutils
  echo "$PROMPT" | gtimeout "$TIMEOUT" claude --dangerously-skip-permissions -p 2>&1 | tee -a "$LOG_FILE"
  EXIT_CODE=${PIPESTATUS[1]:-$?}
elif command -v timeout &>/dev/null; then
  # Linux
  echo "$PROMPT" | timeout "$TIMEOUT" claude --dangerously-skip-permissions -p 2>&1 | tee -a "$LOG_FILE"
  EXIT_CODE=${PIPESTATUS[1]:-$?}
else
  # 无 timeout 命令，用后台进程 + kill 实现
  echo "$PROMPT" | claude --dangerously-skip-permissions -p 2>&1 | tee -a "$LOG_FILE" &
  CLAUDE_PID=$!
  echo "$CLAUDE_PID" > "$PID_FILE"

  # 超时监控
  (
    sleep "$TIMEOUT"
    if kill -0 "$CLAUDE_PID" 2>/dev/null; then
      echo "[claude-worker] ⏰ 超时 (${TIMEOUT}s)，终止 Claude 进程" | tee -a "$LOG_FILE"
      kill "$CLAUDE_PID" 2>/dev/null
    fi
  ) &
  WATCHDOG_PID=$!

  wait "$CLAUDE_PID" 2>/dev/null
  EXIT_CODE=$?

  # 清理 watchdog
  kill "$WATCHDOG_PID" 2>/dev/null
  wait "$WATCHDOG_PID" 2>/dev/null
fi

# ── 收尾 ──────────────────────────────────────────────────
FINISHED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
rm -f "$PID_FILE"

{
  echo "================================================================"
  echo "[claude-worker] finished_at=$FINISHED_AT"
  echo "[claude-worker] exit_code=$EXIT_CODE"
  echo "================================================================"
} | tee -a "$LOG_FILE"

# ── 状态兜底：如果 Claude 没有正确写 status，自动补写 ──────
if [[ -f "$STATUS_FILE" ]]; then
  CURRENT_STATUS="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('status','unknown'))" "$STATUS_FILE" 2>/dev/null || echo "unknown")"
else
  CURRENT_STATUS="unknown"
fi

if [[ "$CURRENT_STATUS" == "running" || "$CURRENT_STATUS" == "unknown" ]]; then
  if [[ $EXIT_CODE -eq 0 ]]; then
    FALLBACK_STATUS="done"
    FALLBACK_SUMMARY="Claude 进程正常退出但未更新状态文件，脚本兜底标记为 done"
    FALLBACK_REASON="null"
  elif [[ $EXIT_CODE -eq 124 ]]; then
    FALLBACK_STATUS="failed"
    FALLBACK_SUMMARY="Claude worker 超时 (${TIMEOUT}s)"
    FALLBACK_REASON="\"claude worker timeout after ${TIMEOUT}s\""
  else
    FALLBACK_STATUS="failed"
    FALLBACK_SUMMARY="Claude 进程异常退出 (exit_code=$EXIT_CODE)"
    FALLBACK_REASON="\"claude exited with code $EXIT_CODE\""
  fi

  echo "[claude-worker] ⚠️  状态兜底: status=$CURRENT_STATUS → $FALLBACK_STATUS" | tee -a "$LOG_FILE"

  cat > "$STATUS_FILE" <<JSON
{
  "status": "$FALLBACK_STATUS",
  "summary": "$FALLBACK_SUMMARY",
  "startedAt": "$STARTED_AT",
  "finishedAt": "$FINISHED_AT",
  "exitCode": $EXIT_CODE,
  "changedFiles": [],
  "commandsRun": [],
  "validation": [],
  "remainingIssues": [],
  "blockedReason": $FALLBACK_REASON
}
JSON
else
  # Claude 正确写了状态，补充 finishedAt 和 exitCode
  python3 -c "
import json, sys
f = sys.argv[1]
d = json.load(open(f))
d['finishedAt'] = sys.argv[2]
d['exitCode'] = int(sys.argv[3])
d['startedAt'] = d.get('startedAt', sys.argv[4])
json.dump(d, open(f, 'w'), ensure_ascii=False, indent=2)
" "$STATUS_FILE" "$FINISHED_AT" "$EXIT_CODE" "$STARTED_AT" 2>/dev/null || true
fi

# 确保产物文件存在（即使是空的）
[[ -f "$RESULT_FILE" ]] || echo "(Claude 未写出 result 文件)" > "$RESULT_FILE"
[[ -f "$CHANGED_FILE" ]] || touch "$CHANGED_FILE"

echo "[claude-worker] 🏁 本轮结束 status=$(python3 -c "import json; print(json.load(open('$STATUS_FILE')).get('status','?'))" 2>/dev/null || echo '?')" | tee -a "$LOG_FILE"
exit $EXIT_CODE
