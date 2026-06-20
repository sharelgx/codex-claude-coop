#!/usr/bin/env bash
# coop_status.sh — 检查一个 loop 目录的当前状态
# 用法: coop_status.sh <loop-dir>

set -uo pipefail

LOOP_DIR="${1:-}"
if [[ -z "$LOOP_DIR" ]]; then
  echo "用法: $0 <loop-dir>" >&2
  exit 2
fi

if [[ ! -d "$LOOP_DIR" ]]; then
  echo "❌ loop 目录不存在: $LOOP_DIR" >&2
  exit 1
fi

STATUS_FILE="$LOOP_DIR/claude_status.json"
RESULT_FILE="$LOOP_DIR/claude_result.md"
CHANGED_FILE="$LOOP_DIR/changed_files.txt"
LOG_FILE="$LOOP_DIR/claude_stdout.log"
PID_FILE="$LOOP_DIR/claude_worker.pid"
TASK_FILE="$LOOP_DIR/current_task.md"
REVIEW_FILE="$LOOP_DIR/codex_review.md"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  coop loop 状态报告                                      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "📁 loop 目录: $LOOP_DIR"
echo ""

# ── 任务文件 ──
if [[ -f "$TASK_FILE" ]]; then
  TASK_SIZE=$(wc -c < "$TASK_FILE" | tr -d ' ')
  TASK_LINES=$(wc -l < "$TASK_FILE" | tr -d ' ')
  echo "📝 任务文件: ✅ 存在 (${TASK_LINES} 行, ${TASK_SIZE} bytes)"
else
  echo "📝 任务文件: ❌ 不存在"
fi

# ── 状态 JSON ──
if [[ -f "$STATUS_FILE" ]]; then
  STATUS=$(python3 -c "import json; d=json.load(open('$STATUS_FILE')); print(d.get('status','unknown'))" 2>/dev/null || echo "解析失败")
  SUMMARY=$(python3 -c "import json; d=json.load(open('$STATUS_FILE')); print(d.get('summary',''))" 2>/dev/null || echo "")
  STARTED=$(python3 -c "import json; d=json.load(open('$STATUS_FILE')); print(d.get('startedAt','?'))" 2>/dev/null || echo "?")
  FINISHED=$(python3 -c "import json; d=json.load(open('$STATUS_FILE')); print(d.get('finishedAt','?'))" 2>/dev/null || echo "?")
  EXIT_CODE=$(python3 -c "import json; d=json.load(open('$STATUS_FILE')); print(d.get('exitCode','?'))" 2>/dev/null || echo "?")
  BLOCKED=$(python3 -c "import json; d=json.load(open('$STATUS_FILE')); r=d.get('blockedReason'); print(r if r else '无')" 2>/dev/null || echo "?")
  CHANGED_COUNT=$(python3 -c "import json; d=json.load(open('$STATUS_FILE')); print(len(d.get('changedFiles',[])))" 2>/dev/null || echo "?")
  ISSUES_COUNT=$(python3 -c "import json; d=json.load(open('$STATUS_FILE')); print(len(d.get('remainingIssues',[])))" 2>/dev/null || echo "?")

  case "$STATUS" in
    done)    STATUS_ICON="✅" ;;
    running) STATUS_ICON="🔄" ;;
    failed)  STATUS_ICON="❌" ;;
    blocked) STATUS_ICON="🚧" ;;
    *)       STATUS_ICON="❓" ;;
  esac

  echo ""
  echo "═══ 状态摘要 ═══"
  echo "  状态:     $STATUS_ICON $STATUS"
  echo "  摘要:     $SUMMARY"
  echo "  开始:     $STARTED"
  echo "  结束:     $FINISHED"
  echo "  退出码:   $EXIT_CODE"
  echo "  改动文件: $CHANGED_COUNT 个"
  echo "  遗留问题: $ISSUES_COUNT 个"
  echo "  阻塞原因: $BLOCKED"
else
  echo ""
  echo "═══ 状态摘要 ═══"
  echo "  ❌ claude_status.json 不存在"
fi

# ── 产物文件检查 ──
echo ""
echo "═══ 产物文件 ═══"

if [[ -f "$RESULT_FILE" ]]; then
  RESULT_SIZE=$(wc -c < "$RESULT_FILE" | tr -d ' ')
  echo "  claude_result.md:   ✅ (${RESULT_SIZE} bytes)"
else
  echo "  claude_result.md:   ❌ 不存在"
fi

if [[ -f "$CHANGED_FILE" ]]; then
  CHANGED_LINES=$(wc -l < "$CHANGED_FILE" | tr -d ' ')
  echo "  changed_files.txt:  ✅ (${CHANGED_LINES} 个文件)"
  if [[ "$CHANGED_LINES" -gt 0 ]]; then
    echo "    ──────────────────"
    head -20 "$CHANGED_FILE" | sed 's/^/    /'
    if [[ "$CHANGED_LINES" -gt 20 ]]; then
      echo "    ... 还有 $((CHANGED_LINES - 20)) 个文件"
    fi
  fi
else
  echo "  changed_files.txt:  ❌ 不存在"
fi

if [[ -f "$REVIEW_FILE" ]]; then
  echo "  codex_review.md:    ✅ (Codex 已审查)"
else
  echo "  codex_review.md:    ⏳ 待审查"
fi

# ── Claude worker 进程状态 ──
echo ""
echo "═══ 进程状态 ═══"

WORKER_RUNNING=false
if [[ -f "$PID_FILE" ]]; then
  SAVED_PID=$(cat "$PID_FILE")
  if kill -0 "$SAVED_PID" 2>/dev/null; then
    echo "  Claude worker PID $SAVED_PID: 🔄 运行中"
    WORKER_RUNNING=true
  else
    echo "  Claude worker PID $SAVED_PID: 💀 已退出"
  fi
else
  # 尝试通过 ps 查找
  CLAUDE_PIDS=$(pgrep -f "claude.*dangerously-skip-permissions" 2>/dev/null || true)
  if [[ -n "$CLAUDE_PIDS" ]]; then
    echo "  检测到 claude 进程: $CLAUDE_PIDS"
    WORKER_RUNNING=true
  else
    echo "  无 claude worker 进程运行"
  fi
fi

# ── 最近修改的文件 ──
echo ""
echo "═══ 最近 10 分钟修改的文件 ═══"
RECENT_FILES=$(find "$LOOP_DIR" -type f -mmin -10 2>/dev/null | head -20)
if [[ -n "$RECENT_FILES" ]]; then
  echo "$RECENT_FILES" | while read -r f; do
    MOD_TIME=$(stat -f '%Sm' -t '%H:%M:%S' "$f" 2>/dev/null || stat -c '%y' "$f" 2>/dev/null | cut -d. -f1 || echo "?")
    echo "  [$MOD_TIME] $f"
  done
else
  echo "  (无)"
fi

# ── 日志尾部 ──
echo ""
echo "═══ 日志尾部 (最近 40 行) ═══"
if [[ -f "$LOG_FILE" ]]; then
  LOG_SIZE=$(wc -c < "$LOG_FILE" | tr -d ' ')
  LOG_LINES=$(wc -l < "$LOG_FILE" | tr -d ' ')
  echo "  日志大小: ${LOG_SIZE} bytes, ${LOG_LINES} 行"
  echo "  ──────────────────"
  tail -40 "$LOG_FILE" | sed 's/^/  /'
else
  echo "  (日志文件不存在)"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
