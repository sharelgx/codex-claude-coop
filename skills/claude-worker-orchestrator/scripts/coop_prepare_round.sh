#!/usr/bin/env bash
# coop_prepare_round.sh — 初始化一个新的 loop 目录
# 用法: coop_prepare_round.sh <loop-slug> [project-root]
#
# 自动生成带时间戳的 loop 目录，创建空模板文件

set -euo pipefail

SLUG="${1:-}"
PROJECT_ROOT="${2:-.}"

if [[ -z "$SLUG" ]]; then
  echo "用法: $0 <loop-slug> [project-root]" >&2
  echo "示例: $0 fix-q7-image /Volumes/Ext2T/Workspaces/k12" >&2
  exit 2
fi

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
LOOP_DIR="$PROJECT_ROOT/tmp/agent_loop/${SLUG}-${TIMESTAMP}"

mkdir -p "$LOOP_DIR"

# 创建任务模板
cat > "$LOOP_DIR/current_task.md" <<'TEMPLATE'
# 本轮任务

## 背景

(Codex 填写背景)

## 本轮目标

(Codex 填写本轮具体目标)

## 必须修改的范围

- (文件/目录)

## 禁止修改的范围

- (文件/目录)

## 验收标准

1. (具体可检查的条件)

## 必须产出的文件

- `claude_status.json`: status 为 done/blocked/failed
- `claude_result.md`: 中文总结
- `changed_files.txt`: 改动文件列表

## 注意事项

- 完成后退出，不要继续等待人工输入
- 所有文档优先中文
TEMPLATE

echo "✅ loop 目录已创建: $LOOP_DIR"
echo ""
echo "下一步:"
echo "  1. 编辑任务: $LOOP_DIR/current_task.md"
echo "  2. 启动 worker:"
echo "     /Users/liulaoshi/.codex/skills/claude-worker-orchestrator/scripts/claude_worker_round.sh $LOOP_DIR"
echo "  3. 检查状态:"
echo "     /Users/liulaoshi/.codex/skills/claude-worker-orchestrator/scripts/coop_status.sh $LOOP_DIR"

# 输出目录路径供调用者使用
echo "$LOOP_DIR"
