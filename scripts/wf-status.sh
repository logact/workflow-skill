#!/usr/bin/env bash
# wf-status.sh — 状态流转，校验合法性，追加 INDEX
# 用法: wf-status.sh <ID> <新状态> [备注]
set -euo pipefail
source "$(dirname "$0")/wf-common.sh"

[ $# -ge 2 ] || { echo "用法: wf-status.sh <ID> <新状态> [备注]" >&2; exit 1; }
id="$1" new="$2" note="${3:-}"

wf_valid_status "$new" || { echo "wf-status: 非法状态 '$new'（合法：待办/进行中/待验收/完成/已搁置/已废弃）" >&2; exit 1; }

f=$(wf_find "$id") || { echo "wf-status: 找不到 ${id}（不在活跃目录，可能已归档）" >&2; exit 1; }
old=$(wf_get_status "$f")

case "${old}→${new}" in
  待办→进行中|待办→已搁置|待办→已废弃) ;;
  进行中→待验收|进行中→已搁置|进行中→已废弃) ;;
  待验收→完成|待验收→进行中|待验收→已废弃) ;;
  已搁置→待办|已搁置→完成|已搁置→已废弃) ;;
  "${old}→${old}") echo "wf-status: $id 已是 '${old}'，无变化" >&2; exit 1;;
  *) echo "wf-status: 非法流转 ${old} → ${new}（完成/已废弃为终态）" >&2; exit 1;;
esac

wf_lock
wf_set_status "$f" "$new"
event="$old → $new"
[ -n "$note" ] && event="${event}（${note}）"
wf_index "$id" "$event"
wf_git_commit "wf: $id $event" "$f" "$WF_DOCS/INDEX.md"
echo "$id: $event"
