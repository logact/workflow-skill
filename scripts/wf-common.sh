#!/usr/bin/env bash
# wf-common.sh — 公共函数。被其他 wf-*.sh source，不直接执行。
# 兼容 macOS 自带 bash 3.2，不用关联数组。

# C locale 下 bash 3.2 会把多字节字符首字节并入变量名（"$x）" 解析成变量 x\xEF...），必须 UTF-8
export LC_ALL=en_US.UTF-8

WF_DOCS="${WF_DOCS:-docs}"

wf_now()   { date "+%Y-%m-%d %H:%M"; }
wf_month() { date "+%Y-%m"; }

wf_prefix_of() { # $1=type → 打印 ID 前缀
  case "$1" in
    decision) echo D;; task) echo T;; issue) echo I;; backlog) echo B;;
    *) echo "wf: 未知类型 '$1'（应为 decision|task|issue|backlog）" >&2; exit 1;;
  esac
}

wf_dir_of() { # $1=type → 打印目录名
  case "$1" in
    decision) echo decisions;; task) echo tasks;; issue) echo issues;; backlog) echo backlog;;
    *) echo "wf: 未知类型 '$1'（应为 decision|task|issue|backlog）" >&2; exit 1;;
  esac
}

wf_valid_status() { # $1=status → 合法返回 0
  case "$1" in 待办|进行中|待验收|完成|已搁置|已废弃) return 0;; *) return 1;; esac
}

wf_lock() { # mkdir 自旋锁，退出时自动释放
  local lockdir="$WF_DOCS/.wf-lock" n=0
  while ! mkdir "$lockdir" 2>/dev/null; do
    n=$((n+1))
    if [ "$n" -gt 400 ]; then echo "wf: 获取锁超时" >&2; exit 1; fi
    sleep 0.05
  done
  trap 'rmdir "'"$lockdir"'" 2>/dev/null || true' EXIT
}

wf_index() { # $1=文件ID $2=事件 $3=操作者(默认 wf)
  printf '%s | %s | %s | %s\n' "$(wf_now)" "$1" "$2" "${3:-wf}" >> "$WF_DOCS/INDEX.md"
}

wf_next_id() { # $1=type → 打印下一个 ID（扫活跃目录 + _archive，全局递增不回收）
  local prefix dir f id n max=0
  prefix=$(wf_prefix_of "$1"); dir=$(wf_dir_of "$1")
  [ -d "$WF_DOCS/$dir" ] || { printf '%s-0001' "$prefix"; return; }
  while IFS= read -r f; do
    id=$(sed -n 's/^id: \([A-Z]-[0-9]\{4\}\).*/\1/p' "$f" | head -1)
    [ -n "$id" ] || continue
    [ "${id%%-*}" = "$prefix" ] || continue
    n=$((10#${id##*-}))
    [ "$n" -gt "$max" ] && max=$n
  done < <(find "$WF_DOCS/$dir" -type f -name '*.md' 2>/dev/null)
  printf '%s-%04d' "$prefix" $((max+1))
}

wf_find() { # $1=ID → 打印文件路径（只找活跃目录，不含 _archive）；找不到返回 1
  local d f
  for d in decisions tasks issues backlog; do
    [ -d "$WF_DOCS/$d" ] || continue
    while IFS= read -r f; do
      if grep -q "^id: $1\$" "$f" 2>/dev/null; then echo "$f"; return 0; fi
    done < <(find "$WF_DOCS/$d" -type f -name '*.md' -not -path '*/_archive/*')
  done
  return 1
}

wf_get_status() { # $1=文件 → 打印 status（去尾注释和空白）
  sed -n '/^---$/,/^---$/ s/^status: *\(.*\)/\1/p' "$1" | head -1 | sed 's/#.*//; s/ *$//'
}

wf_get_field() { # $1=文件 $2=字段名 → 打印值
  sed -n "/^---\$/,/^---\$/ s/^$2: *\\(.*\\)/\\1/p" "$1" | head -1 | sed 's/ *$//'
}

wf_set_status() { # $1=文件 $2=新状态
  sed -i '' "/^---$/,/^---$/ s/^status:.*/status: $2/" "$1"
}

wf_set_field() { # $1=文件 $2=字段名 $3=新值
  sed -i '' "/^---$/,/^---$/ s/^$2:.*/$2: $3/" "$1"
}

wf_git_commit() { # $1=提交信息，其余=变更的文件路径；不在 git 仓库或路径被 ignore 时静默跳过，提交失败仅告警
  local msg="$1"; shift
  command -v git >/dev/null 2>&1 || return 0
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  git check-ignore -q "$1" 2>/dev/null && return 0
  git add -- "$@" || { echo "wf: git add 失败，记录已写入但未提交，请手工提交" >&2; return 0; }
  git diff --cached --quiet && return 0
  git commit -q -m "$msg" || echo "wf: git commit 失败，改动已暂存，请手工提交" >&2
}
