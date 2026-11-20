#!/usr/bin/env bash
# wf-daemon.sh — 守护调度器：自动把"可执行的待办任务"派发到 Orca worktree 执行（D-0005/D-0006）
# 用法:
#   wf-daemon.sh once                  跑一趟调度（检查已合并分支收口 + 派发一个可执行任务）
#   wf-daemon.sh start [--interval N]  后台循环（默认 60 秒）
#   wf-daemon.sh stop                  停止后台循环
#   wf-daemon.sh status                查看是否在跑
# 环境变量:
#   WF_DAEMON_AGENT   派发用的 agent id（默认 claude）
#   WF_DAEMON_DRYRUN  =1 时只打印调度决策，不改状态、不调 orca（测试用）
set -euo pipefail
source "$(dirname "$0")/wf-common.sh"

AGENT="${WF_DAEMON_AGENT:-claude}"
DRYRUN="${WF_DAEMON_DRYRUN:-0}"
PIDFILE="$WF_DOCS/.wf-daemon.pid"
INTERVAL=60

wf_find_any() { # $1=ID → 打印文件路径（含 _archive，已完成的依赖可能已归档）
  local d f
  for d in decisions tasks issues backlog; do
    [ -d "$WF_DOCS/$d" ] || continue
    while IFS= read -r f; do
      if grep -q "^id: $1\$" "$f" 2>/dev/null; then echo "$f"; return 0; fi
    done < <(find "$WF_DOCS/$d" -type f -name '*.md' 2>/dev/null)
  done
  return 1
}

wf_deps_done() { # $1=任务文件 → 所有 depends_on 均为"完成"返回 0
  local f="$1" deps dep df st
  deps=$(wf_get_field "$f" depends_on | sed 's/#.*//')
  [ -n "$deps" ] || return 0
  for dep in $(printf '%s' "$deps" | tr ',' ' '); do
    df=$(wf_find_any "$dep") || { echo "wf-daemon: $(wf_get_field "$f" id) 的前置 $dep 不存在，跳过" >&2; return 1; }
    st=$(wf_get_status "$df")
    [ "$st" = "完成" ] || return 1
  done
  return 0
}

wf_pick_task() { # → 打印 "id|priority|file"（优先级 高>中>低，同级按 ID 升序）；没有则空
  local best="" bestid="" bestrank=99 f st pr rank tid
  for f in "$WF_DOCS"/tasks/T-*.md; do
    [ -e "$f" ] || continue
    st=$(wf_get_status "$f")
    [ "$st" = "待办" ] || continue
    wf_deps_done "$f" || continue
    pr=$(wf_get_field "$f" priority)
    case "$pr" in 高) rank=0;; 中) rank=1;; *) rank=2;; esac
    tid=$(wf_get_field "$f" id)
    if [ "$rank" -lt "$bestrank" ] || { [ "$rank" -eq "$bestrank" ] && [ -n "$bestid" ] && [[ "$tid" < "$bestid" ]]; }; then
      bestrank=$rank; bestid=$tid; best="$tid|$pr|$f"
    fi
  done
  printf '%s' "$best"
}

wf_dispatch() { # $1=id $2=任务文件
  local id="$1" f="$2" root prompt json wt branch
  root=$(pwd -P)
  if [ "$DRYRUN" = "1" ]; then
    echo "wf-daemon: [dryrun] 将派发 ${id}（priority $(wf_get_field "$f" priority)）→ orca worktree create --agent $AGENT"
    return 0
  fi
  bash "$(dirname "$0")/wf-status.sh" "$id" 进行中 "守护调度器派发" >/dev/null
  prompt="你正在 Orca worktree 中执行任务 ${id}。先阅读本 checkout 里的 ${f#./} 以及 $WF_DOCS/PRD.md、$WF_DOCS/README.md 了解任务目标与项目规则。要求：1) 在本 worktree 当前分支上实现任务目标并自测；2) 自测通过后把本分支合并回主分支（main）并解决冲突，合并成功即结果层面验收通过；3) 合并成功后运行：WF_DOCS='$root/$WF_DOCS' bash '$root/scripts/wf-status.sh' $id 待验收 '分支已合并主分支'；4) 过程记录追加到 $root/$WF_DOCS/logs/。注意：所有记录操作只对主 checkout（${root}）执行，不要改本 worktree 里的 docs/。"
  if ! json=$(orca worktree create --name "$id" --agent "$AGENT" --prompt "$prompt" --json 2>&1); then
    echo "wf-daemon: orca worktree create 失败：$json" >&2
    echo "wf-daemon: $id 保持进行中，请人工处理" >&2
    return 1
  fi
  wt=$(printf '%s' "$json" | grep -o '"id"[^,}]*' | grep '::' | head -1 | sed 's/.*"\([^"]*::[^"]*\)".*/\1/')
  branch=$(printf '%s' "$json" | grep -o '"branch"[^,}]*' | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
  [ -n "$branch" ] || branch="$id"
  wf_set_field "$f" worktree "$wt"
  wf_set_field "$f" branch "$branch"
  wf_index "$id" "派发至 worktree（分支 ${branch}）"
  wf_git_commit "wf: ${id} 派发至 worktree（分支 ${branch}）" "$f" "$WF_DOCS/INDEX.md"
  echo "wf-daemon: 已派发 $id → worktree（分支 $branch）"
}

wf_collect_merged() { # 收口：进行中任务的分支已合并回主分支 → 转待验收
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local main_branch="" f st br id
  for mb in main master; do
    if git show-ref --verify --quiet "refs/heads/$mb"; then main_branch="$mb"; break; fi
  done
  [ -n "$main_branch" ] || return 0
  for f in "$WF_DOCS"/tasks/T-*.md; do
    [ -e "$f" ] || continue
    st=$(wf_get_status "$f")
    [ "$st" = "进行中" ] || continue
    br=$(wf_get_field "$f" branch | sed 's/#.*//')
    [ -n "$br" ] || continue
    id=$(wf_get_field "$f" id)
    if git merge-base --is-ancestor "$br" "$main_branch" 2>/dev/null; then
      if [ "$DRYRUN" = "1" ]; then
        echo "wf-daemon: [dryrun] $id 分支 $br 已合并 $main_branch，将转待验收"
      else
        bash "$(dirname "$0")/wf-status.sh" "$id" 待验收 "分支 ${br} 已合并 ${main_branch}" >/dev/null
        echo "wf-daemon: $id 分支已合并 $main_branch → 待验收"
      fi
    fi
  done
}

cmd="${1:-}"
[ $# -gt 0 ] && shift
while [ $# -gt 0 ]; do
  case "$1" in --interval) INTERVAL="$2"; shift 2;; *) echo "wf-daemon: 未知参数 $1" >&2; exit 1;; esac
done

case "$cmd" in
  once)
    wf_collect_merged
    t=$(wf_pick_task)
    if [ -n "$t" ]; then
      wf_dispatch "${t%%|*}" "${t##*|}"
    else
      echo "wf-daemon: 没有可执行的任务（待办且前置全部完成）"
    fi
    ;;
  start)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "wf-daemon: 已在运行（pid $(cat "$PIDFILE")）"; exit 0
    fi
    nohup bash "$0" __loop --interval "$INTERVAL" >/dev/null 2>&1 &
    echo $! > "$PIDFILE"
    echo "wf-daemon: 已启动（pid $!，间隔 ${INTERVAL}s）"
    ;;
  stop)
    if [ ! -f "$PIDFILE" ]; then echo "wf-daemon: 未在运行"; exit 0; fi
    pid=$(cat "$PIDFILE")
    if kill "$pid" 2>/dev/null; then echo "wf-daemon: 已停止（pid ${pid}）"; else echo "wf-daemon: 进程不存在，清理 pidfile"; fi
    rm -f "$PIDFILE"
    ;;
  status)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "wf-daemon: 运行中（pid $(cat "$PIDFILE")）"
    else
      echo "wf-daemon: 未在运行"
    fi
    ;;
  __loop)
    trap 'rm -f "$PIDFILE"' EXIT
    while :; do
      bash "$0" once || true
      sleep "$INTERVAL"
    done
    ;;
  *)
    echo "用法: wf-daemon.sh <once|start [--interval N]|stop|status>" >&2; exit 1;;
esac
