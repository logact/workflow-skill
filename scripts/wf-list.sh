#!/usr/bin/env bash
# wf-list.sh — 列出活跃记录的当前状态（只读，不改任何文件）
# 用法: wf-list.sh [decision|task|issue|backlog] [状态]
set -euo pipefail
source "$(dirname "$0")/wf-common.sh"

type_filter="${1:-}" status_filter="${2:-}"

if [ -n "$type_filter" ]; then
  wf_dir_of "$type_filter" >/dev/null   # 复用类型校验
fi
if [ -n "$status_filter" ]; then
  wf_valid_status "$status_filter" || { echo "wf-list: 非法状态 '$status_filter'（合法：待办/进行中/待验收/完成/已搁置/已废弃）" >&2; exit 1; }
fi

if [ -n "$type_filter" ]; then
  dirs=$(wf_dir_of "$type_filter")
else
  dirs="decisions tasks issues backlog"
fi

found=0
for d in $dirs; do
  [ -d "$WF_DOCS/$d" ] || continue
  while IFS= read -r f; do
    case "$f" in */_template.md) continue;; esac
    id=$(wf_get_field "$f" id)
    [ -n "$id" ] || continue
    st=$(wf_get_status "$f")
    [ -n "$status_filter" ] && [ "$st" != "$status_filter" ] && continue
    title=$(sed -n 's/^# //p' "$f" | head -1)
    printf '%s | %s | %s | %s\n' "$id" "$st" "$title" "$d"
    found=1
  done < <(find "$WF_DOCS/$d" -type f -name '*.md' -not -path '*/_archive/*')
done

[ "$found" -eq 1 ] || echo "wf-list: 没有匹配的记录（归档文件不在列，查历史用 wf-query.sh）" >&2
