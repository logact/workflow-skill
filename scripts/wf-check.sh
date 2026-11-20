#!/usr/bin/env bash
# wf-check.sh — 一致性校验：frontmatter 合法、ID 无重复、ID 引用可解析、INDEX 格式正确
set -euo pipefail
source "$(dirname "$0")/wf-common.sh"

errors=0
err() { echo "wf-check: ✗ $1" >&2; errors=$((errors+1)); }

all_files=$(mktemp)
all_ids=$(mktemp)
trap 'rm -f "$all_files" "$all_ids"' EXIT

for d in decisions tasks issues backlog; do
  [ -d "$WF_DOCS/$d" ] || continue
  find "$WF_DOCS/$d" -type f -name '*.md' >> "$all_files"
done

# 1. frontmatter 校验（跳过模板），收集 ID
: > "$all_ids"
while IFS= read -r f; do
  case "$(basename "$f")" in _template.md) continue;; esac
  id=$(wf_get_field "$f" id)
  ty=$(wf_get_field "$f" type)
  st=$(wf_get_status "$f")
  [ -n "$id" ] || err "$f 缺少 id"
  [ -n "$ty" ] || err "$f 缺少 type"
  wf_valid_status "$st" || err "$f status 非法: '$st'"
  if [ "$ty" = task ]; then
    pr=$(wf_get_field "$f" priority)
    case "$pr" in 高|中|低) ;; *) err "$f priority 非法: '$pr'（合法：高/中/低）";; esac
  fi
  [ -n "$id" ] && echo "$id" >> "$all_ids"
done < "$all_files"

# 2. ID 重复检测
dup=$(sort "$all_ids" | uniq -d)
[ -z "$dup" ] || err "ID 重复: $(echo $dup | tr '\n' ' ')"

# 3. ID 引用可解析（正文里出现的 X-0000 形式的 ID 必须存在）
while IFS= read -r f; do
  case "$(basename "$f")" in _template.md) continue;; esac
  refs=$(grep -o '[DTIB]-[0-9]\{4\}' "$f" | sort -u || true)
  for r in $refs; do
    grep -qx "$r" "$all_ids" || err "$f 引用了不存在的 $r"
  done
done < "$all_files"

# 4. INDEX 格式：数据行必须是 "YYYY-MM-DD HH:MM | 对象 | 事件 | 操作者"
if [ -f "$WF_DOCS/INDEX.md" ]; then
  bad=$(grep -E '^[0-9]{4}-' "$WF_DOCS/INDEX.md" \
        | grep -cvE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \| [^|]+ \| [^|]+ \| [^|]+$' || true)
  [ "$bad" -eq 0 ] || err "INDEX.md 有 $bad 行格式不符"
else
  err "缺少 INDEX.md"
fi

if [ "$errors" -eq 0 ]; then
  echo "wf-check: ✓ 全部通过"
else
  echo "wf-check: 共 $errors 个问题" >&2
  exit 1
fi
