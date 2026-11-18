#!/usr/bin/env bash
# wf-query.sh — 查询单个记录的当前状态与 INDEX 事件历史（只读，不改任何文件）
# 用法: wf-query.sh <ID>
set -euo pipefail
source "$(dirname "$0")/wf-common.sh"

[ $# -ge 1 ] || { echo "用法: wf-query.sh <ID>" >&2; exit 1; }
id="$1"

archived=""
if ! f=$(wf_find "$id"); then
  # 活跃目录没有，退到 _archive 里找
  f=$(find "$WF_DOCS" -path '*/_archive/*' -name "$id-*.md" -type f 2>/dev/null | head -1)
  [ -n "$f" ] || { echo "wf-query: 找不到 $id（活跃目录和 _archive 都没有）" >&2; exit 1; }
  archived="（已归档）"
fi

title=$(sed -n 's/^# //p' "$f" | head -1)
echo "ID:     $id"
echo "类型:   $(wf_get_field "$f" type)"
echo "状态:   $(wf_get_status "$f")$archived"
echo "标题:   $title"
echo "文件:   $f"

echo "---"
echo "INDEX 事件历史："
if [ -f "$WF_DOCS/INDEX.md" ]; then
  grep " | $id | " "$WF_DOCS/INDEX.md" || echo "（INDEX 中无 $id 的事件）"
else
  echo "（$WF_DOCS/INDEX.md 不存在）"
fi
