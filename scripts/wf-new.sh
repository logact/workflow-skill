#!/usr/bin/env bash
# wf-new.sh — 创建记录文件，自动分配 ID，追加 INDEX
# 用法: wf-new.sh <decision|task|issue|backlog> <标题> [--source ID|PRD] [--supersedes D-xxxx]
set -euo pipefail
source "$(dirname "$0")/wf-common.sh"

type="" title="" source_ref="" supersedes=""
while [ $# -gt 0 ]; do
  case "$1" in
    --source) source_ref="$2"; shift 2;;
    --supersedes) supersedes="$2"; shift 2;;
    --*) echo "wf-new: 未知参数 $1" >&2; exit 1;;
    *) if [ -z "$type" ]; then type="$1"; elif [ -z "$title" ]; then title="$1"; else echo "wf-new: 多余参数 $1" >&2; exit 1; fi; shift;;
  esac
done
[ -n "$type" ] && [ -n "$title" ] || { echo "用法: wf-new.sh <decision|task|issue|backlog> <标题> [--source ID|PRD] [--supersedes D-xxxx]" >&2; exit 1; }

dir=$(wf_dir_of "$type")   # 同时校验类型合法
[ -d "$WF_DOCS/$dir" ] || { echo "wf-new: $WF_DOCS/$dir 不存在，先运行 wf-init.sh" >&2; exit 1; }

wf_lock
id=$(wf_next_id "$type")
today=$(date "+%Y-%m-%d")

case "$type" in
  decision) status="完成";;
  backlog)  status="已搁置";;
  *)        status="待办";;
esac

case "$type" in
  decision) body="## 决策内容

## 背景与理由

## 影响范围
";;
  task) body="## 目标

## 验收标准
- [ ] 结果层面：
- [ ] 日志层面：docs/logs/ 中有对应记录

## 验收记录
";;
  issue) body="## 现象

## 复现 / 验证方式

## 处理记录
";;
  backlog) body="## 条目描述

## 回流记录
";;
esac

superseded_line=""
[ "$type" = decision ] && superseded_line="superseded_by:"

cat > "$WF_DOCS/$dir/$id-$title.md" <<EOF
---
id: $id
type: $type
status: $status
created: $today
source: $source_ref
$superseded_line
---

# $title

$body
EOF

if [ -n "$supersedes" ]; then
  old=$(wf_find "$supersedes") || { echo "wf-new: 被取代的决策 $supersedes 不存在" >&2; exit 1; }
  wf_set_status "$old" "已废弃"
  wf_set_field "$old" "superseded_by" "$id"
  wf_index "$supersedes" "已被 $id 取代"
fi

wf_index "$id" "创建（${title}）"
echo "$id"
