#!/usr/bin/env bash
# wf-archive.sh — 归档终态文件到 _archive/YYYY-MM/
# 规则：完成/已废弃才归档；未被取代的决策永不归档；已搁置不归档。
set -euo pipefail
source "$(dirname "$0")/wf-common.sh"

month=$(wf_month)
count=0

for d in decisions tasks issues backlog; do
  [ -d "$WF_DOCS/$d" ] || continue
  while IFS= read -r f; do
    base=$(basename "$f")
    [ "$base" = "_template.md" ] && continue
    st=$(wf_get_status "$f")
    case "$st" in 完成|已废弃) ;; *) continue;; esac
    if [ "$d" = decisions ] && [ "$st" = 完成 ]; then
      sup=$(wf_get_field "$f" superseded_by)
      [ -z "$sup" ] && continue   # 未被取代的决策永不归档
    fi
    id=$(wf_get_field "$f" id)
    dest="$WF_DOCS/$d/_archive/$month"
    mkdir -p "$dest"
    mv "$f" "$dest/$base"
    wf_index "$id" "归档 → $d/_archive/$month"
    echo "归档: $id → $d/_archive/$month/$base"
    count=$((count+1))
  done < <(find "$WF_DOCS/$d" -maxdepth 1 -type f -name '*.md')
done

echo "wf-archive: 共归档 $count 个文件"
