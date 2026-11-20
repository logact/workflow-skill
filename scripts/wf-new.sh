#!/usr/bin/env bash
# wf-new.sh — 创建记录文件，自动分配 ID，追加 INDEX
# 用法: wf-new.sh <decision|task|issue|backlog> <标题> [--source ID|PRD] [--supersedes D-xxxx] [--priority 高|中|低] [--depends-on T-xxxx,...]
set -euo pipefail
source "$(dirname "$0")/wf-common.sh"

type="" title="" source_ref="" supersedes="" priority="" depends_on=""
while [ $# -gt 0 ]; do
  case "$1" in
    --source) source_ref="$2"; shift 2;;
    --supersedes) supersedes="$2"; shift 2;;
    --priority) priority="$2"; shift 2;;
    --depends-on) depends_on="$2"; shift 2;;
    --*) echo "wf-new: 未知参数 $1" >&2; exit 1;;
    *) if [ -z "$type" ]; then type="$1"; elif [ -z "$title" ]; then title="$1"; else echo "wf-new: 多余参数 $1" >&2; exit 1; fi; shift;;
  esac
done
[ -n "$type" ] && [ -n "$title" ] || { echo "用法: wf-new.sh <decision|task|issue|backlog> <标题> [--source ID|PRD] [--supersedes D-xxxx] [--priority 高|中|低] [--depends-on T-xxxx,...]" >&2; exit 1; }

dir=$(wf_dir_of "$type")   # 同时校验类型合法
[ -d "$WF_DOCS/$dir" ] || { echo "wf-new: $WF_DOCS/$dir 不存在，先运行 wf-init.sh" >&2; exit 1; }

# priority / depends-on 只对任务有意义
if [ "$type" != task ]; then
  [ -z "$priority" ] && [ -z "$depends_on" ] || { echo "wf-new: --priority/--depends-on 只适用于 task" >&2; exit 1; }
fi
if [ "$type" = task ]; then
  priority="${priority:-中}"
  case "$priority" in 高|中|低) ;; *) echo "wf-new: 非法优先级 '$priority'（合法：高/中/低）" >&2; exit 1;; esac
fi

wf_lock
id=$(wf_next_id "$type")
today=$(date "+%Y-%m-%d")
fname=$(printf '%s' "$id-$title" | tr '/' '-')   # 标题里的 / 不能进文件名

case "$type" in
  decision) status="完成";;
  backlog)  status="已搁置";;
  task)     status="起草";;
  *)        status="待办";;
esac

case "$type" in
  decision) body="## 决策内容

## 背景与理由

## 影响范围
";;
  task) body="## 目标

## 验收标准
- [ ] 结果层面：worktree 分支合并回主分支（合并提交存在即通过）
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

ticket_lines=""
if [ "$type" = task ]; then
  ticket_lines="priority: $priority
depends_on: $depends_on
worktree:
branch:"
fi

cat > "$WF_DOCS/$dir/$fname.md" <<EOF
---
id: $id
type: $type
status: $status
created: $today
source: $source_ref
$ticket_lines
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

wf_git_commit "wf: 创建 ${id}（${title}）" "$WF_DOCS/$dir/$fname.md" "$WF_DOCS/INDEX.md" ${supersedes:+"$old"}
echo "$id"
