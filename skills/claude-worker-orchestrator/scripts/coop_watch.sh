#!/usr/bin/env bash
# coop_watch.sh — 实时监控 loop 目录变化
# 用法: coop_watch.sh <loop-dir>
# 每 5 秒刷新一次状态 + 日志增量

set -uo pipefail

LOOP_DIR="${1:-}"
if [[ -z "$LOOP_DIR" ]]; then
  echo "用法: $0 <loop-dir>" >&2
  exit 2
fi

STATUS_FILE="$LOOP_DIR/claude_status.json"
LOG_FILE="$LOOP_DIR/claude_stdout.log"
LAST_LOG_LINES=0

echo "👁️  监控 loop 目录: $LOOP_DIR"
echo "   按 Ctrl+C 停止"
echo ""

while true; do
  clear 2>/dev/null || true

  echo "╔═══════════════════════════════════════════════════╗"
  echo "║  coop watch — $(date '+%H:%M:%S')                          ║"
  echo "╚═══════════════════════════════════════════════════╝"
  echo ""

  # 状态
  if [[ -f "$STATUS_FILE" ]]; then
    STATUS=$(python3 -c "import json; d=json.load(open('$STATUS_FILE')); print(d.get('status','?'))" 2>/dev/null || echo "?")
    SUMMARY=$(python3 -c "import json; d=json.load(open('$STATUS_FILE')); print(d.get('summary',''))" 2>/dev/null || echo "")
    case "$STATUS" in
      done)    echo "  状态: ✅ $STATUS — $SUMMARY" ;;
      running) echo "  状态: 🔄 $STATUS — $SUMMARY" ;;
      failed)  echo "  状态: ❌ $STATUS — $SUMMARY" ;;
      blocked) echo "  状态: 🚧 $STATUS — $SUMMARY" ;;
      *)       echo "  状态: ❓ $STATUS — $SUMMARY" ;;
    esac
  else
    echo "  状态: ⏳ 等待中 (无 status 文件)"
  fi

  # 进程
  CLAUDE_PIDS=$(pgrep -f "claude.*dangerously-skip-permissions" 2>/dev/null || true)
  if [[ -n "$CLAUDE_PIDS" ]]; then
    echo "  进程: 🔄 PID=$CLAUDE_PIDS"
  else
    echo "  进程: 💤 无 claude 进程"
  fi

  # 产物
  echo ""
  for f in claude_result.md changed_files.txt codex_review.md; do
    if [[ -f "$LOOP_DIR/$f" ]]; then
      echo "  📄 $f: ✅"
    else
      echo "  📄 $f: ⏳"
    fi
  done

  # 日志增量
  echo ""
  if [[ -f "$LOG_FILE" ]]; then
    CURRENT_LINES=$(wc -l < "$LOG_FILE" | tr -d ' ')
    NEW_LINES=$((CURRENT_LINES - LAST_LOG_LINES))
    if [[ $NEW_LINES -gt 0 ]]; then
      echo "  ═══ 新增日志 (+$NEW_LINES 行) ═══"
      tail -n "$NEW_LINES" "$LOG_FILE" | tail -30 | sed 's/^/  /'
    else
      echo "  ═══ 日志无变化 (共 $CURRENT_LINES 行) ═══"
      tail -5 "$LOG_FILE" | sed 's/^/  /'
    fi
    LAST_LOG_LINES=$CURRENT_LINES
  else
    echo "  (无日志文件)"
  fi

  # 如果已完成，退出 watch
  if [[ -f "$STATUS_FILE" ]]; then
    FINAL=$(python3 -c "import json; print(json.load(open('$STATUS_FILE')).get('status',''))" 2>/dev/null || echo "")
    if [[ "$FINAL" == "done" || "$FINAL" == "failed" || "$FINAL" == "blocked" ]]; then
      echo ""
      echo "  🏁 Worker 已结束 ($FINAL)，watch 退出"
      exit 0
    fi
  fi

  sleep 5
done
