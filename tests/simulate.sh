#!/usr/bin/env bash
# tests/simulate.sh — 在两个不同类型的测试 domain 中完整模拟 PRD 流程场景
# 用法: bash tests/simulate.sh   （每次运行先清空 tests/run/，可重复执行）
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
RUN="$REPO/tests/run"
SCRIPTS="$REPO/scripts"
MONTH=$(date "+%Y-%m")

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  ✗ $1" >&2; }
assert() { # $1=描述 $2...=命令
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}
assert_grep() { # $1=描述 $2=模式 $3=文件
  if grep -q "$2" "$3" 2>/dev/null; then ok "$1"; else bad "$1"; fi
}

run_domain() { # $1=域名 $2=flavor(script|docs)
  local name="$1" flavor="$2"
  local dir="$RUN/$name"
  echo "== domain: $name ($flavor) =="
  mkdir -p "$dir" && cd "$dir" || return 1

  # domain 自身内容（两种类型，互不依赖）
  if [ "$flavor" = script ]; then echo '#!/usr/bin/env bash' > main.sh; else echo '# 指南' > guide.md; fi

  # 1. 初始化结构（含幂等）
  bash "$SCRIPTS/wf-init.sh" >/dev/null
  bash "$SCRIPTS/wf-init.sh" >/dev/null   # 第二次必须幂等
  assert "初始化: decisions/tasks/issues/backlog/logs 存在" bash -c '[ -d docs/decisions ] && [ -d docs/tasks ] && [ -d docs/issues ] && [ -d docs/backlog ] && [ -d docs/logs ]'
  assert "初始化: README/INDEX/模板就位" bash -c '[ -f docs/README.md ] && [ -f docs/INDEX.md ] && [ -f docs/tasks/_template.md ]'

  # 2. 决策 + 决策变更（取代）
  D1=$(bash "$SCRIPTS/wf-new.sh" decision "用JSON存记录")
  D2=$(bash "$SCRIPTS/wf-new.sh" decision "改用Markdown文件存记录" --supersedes "$D1")
  assert_grep "旧决策 $D1 标记 superseded_by: $D2" "superseded_by: $D2" docs/decisions/$D1-*.md
  assert_grep "旧决策 $D1 状态为已废弃" "status: 已废弃" docs/decisions/$D1-*.md
  assert "新决策 $D2 落地即完成" grep -q "status: 完成" docs/decisions/$D2-*.md

  # 3. 任务（带双层验收标准，创建即"起草"，审批后才可执行）
  T1=$(bash "$SCRIPTS/wf-new.sh" task "实现核心功能" --source PRD)
  assert_grep "任务 $T1 初始状态起草" "status: 起草" docs/tasks/$T1-*.md
  assert_grep "任务 $T1 验收标准含结果层面" "结果层面" docs/tasks/$T1-*.md
  assert_grep "任务 $T1 验收标准含日志层面" "日志层面" docs/tasks/$T1-*.md
  assert_grep "任务 $T1 默认优先级中" "priority: 中" docs/tasks/$T1-*.md
  if bash "$SCRIPTS/wf-status.sh" "$T1" 进行中 >/dev/null 2>&1; then bad "起草直接转进行中被拒绝"; else ok "起草直接转进行中被拒绝"; fi
  bash "$SCRIPTS/wf-status.sh" "$T1" 待办 "审批通过" >/dev/null
  assert_grep "任务 $T1 审批后待办" "status: 待办" docs/tasks/$T1-*.md

  # 4. 问题（一个问题一个文件，来源可追溯）
  I1=$(bash "$SCRIPTS/wf-new.sh" issue "输出格式错误" --source "$T1")
  assert_grep "问题 $I1 记录来源 $T1" "source: $T1" docs/issues/$I1-*.md

  # 5. 多 agent 并行：同时创建 3 个问题，ID 不冲突，INDEX 只追加无写冲突
  bash "$SCRIPTS/wf-new.sh" issue "并行问题A" >/dev/null &
  bash "$SCRIPTS/wf-new.sh" issue "并行问题B" >/dev/null &
  bash "$SCRIPTS/wf-new.sh" issue "并行问题C" >/dev/null &
  wait
  local n_ids n_index
  n_ids=$(grep -h '^id: I-' docs/issues/I-*.md | sort -u | wc -l | tr -d ' ')
  n_index=$(grep -c '创建（并行问题' docs/INDEX.md)
  assert "并行创建: 4 个问题 ID 全部唯一" bash -c "[ '$n_ids' -eq 4 ]"
  assert "并行创建: INDEX 3 条事件无丢失" bash -c "[ '$n_index' -eq 3 ]"

  # 6. 验收循环：通过 + 不通过（无死端）
  bash "$SCRIPTS/wf-status.sh" "$T1" 进行中 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$T1" 待验收 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$T1" 完成 >/dev/null
  assert_grep "$T1 验收通过到完成" "status: 完成" docs/tasks/$T1-*.md

  T2=$(bash "$SCRIPTS/wf-new.sh" task "修复输出格式" --source "$I1")
  bash "$SCRIPTS/wf-status.sh" "$T2" 待办 "审批通过" >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$T2" 进行中 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$T2" 待验收 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$T2" 进行中 "验收不通过" >/dev/null   # 回到进行中
  I2=$(bash "$SCRIPTS/wf-new.sh" issue "修复后仍有边界错误" --source "$T2")
  assert_grep "验收不通过派生问题 $I2" "source: $T2" docs/issues/$I2-*.md
  bash "$SCRIPTS/wf-status.sh" "$T2" 待验收 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$T2" 完成 >/dev/null
  assert_grep "$T2 第二轮验收通过" "status: 完成" docs/tasks/$T2-*.md
  # 非法流转必须被拒绝（终态不可变）
  if bash "$SCRIPTS/wf-status.sh" "$T2" 进行中 >/dev/null 2>&1; then bad "终态任务被拒绝再次流转"; else ok "终态任务被拒绝再次流转"; fi

  # 7. backlog 回流：条目升级为任务
  B1=$(bash "$SCRIPTS/wf-new.sh" backlog "支持导出HTML")
  assert_grep "backlog $B1 初始为已搁置" "status: 已搁置" docs/backlog/$B1-*.md
  T3=$(bash "$SCRIPTS/wf-new.sh" task "实现HTML导出" --source "$B1")
  bash "$SCRIPTS/wf-status.sh" "$B1" 完成 "回流扫描后已升级为 $T3" >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$T3" 待办 "审批通过" >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$T3" 进行中 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$T3" 待验收 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$T3" 完成 >/dev/null
  assert_grep "backlog 升级的任务 $T3 记录来源" "source: $B1" docs/tasks/$T3-*.md

  # 7.5 查询：wf-list 按类型/状态过滤，wf-query 输出当前状态与事件历史
  assert "wf-list 全部: 含任务 $T3" bash -c "bash '$SCRIPTS/wf-list.sh' | grep -q '$T3'"
  assert "wf-list 按类型: task 含 $T1 不含 $I1" bash -c "bash '$SCRIPTS/wf-list.sh' task | grep -q '$T1' && ! bash '$SCRIPTS/wf-list.sh' task | grep -q '$I1'"
  assert "wf-list 按状态: issue+待办 含 $I1" bash -c "bash '$SCRIPTS/wf-list.sh' issue 待办 | grep -q '$I1'"
  assert "wf-list 非法状态被拒绝" bash -c "! bash '$SCRIPTS/wf-list.sh' task 不存在的状态 2>/dev/null"
  assert "wf-query 输出当前状态" bash -c "bash '$SCRIPTS/wf-query.sh' '$T1' | grep -q '状态:   完成'"
  assert "wf-query 输出 INDEX 事件历史" bash -c "bash '$SCRIPTS/wf-query.sh' '$T1' | grep -q '创建（'"
  assert "wf-query 不存在的 ID 报错" bash -c "! bash '$SCRIPTS/wf-query.sh' T-9999 2>/dev/null"

  # 7.8 守护调度（D-0005/D-0006）：起草不派发、依赖阻塞、优先级排序
  TD1=$(bash "$SCRIPTS/wf-new.sh" task "低优任务" --priority 低)
  TD2=$(bash "$SCRIPTS/wf-new.sh" task "高优依赖低优" --priority 高 --depends-on "$TD1")
  TD3=$(bash "$SCRIPTS/wf-new.sh" task "高优无依赖" --priority 高)
  assert_grep "任务 $TD1 带 priority 字段" "priority: 低" docs/tasks/$TD1-*.md
  assert_grep "任务 $TD2 带 depends_on 字段" "depends_on: $TD1" docs/tasks/$TD2-*.md
  assert "非任务类型拒绝 --priority" bash -c "! bash '$SCRIPTS/wf-new.sh' issue 'x' --priority 高 2>/dev/null"
  assert "非法优先级被拒绝" bash -c "! bash '$SCRIPTS/wf-new.sh' task 'x' --priority 最高 2>/dev/null"
  assert "起草中的任务不被调度" bash -c "WF_DAEMON_DRYRUN=1 bash '$SCRIPTS/wf-daemon.sh' once | grep -q '没有可执行的任务'"
  bash "$SCRIPTS/wf-status.sh" "$TD1" 待办 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$TD2" 待办 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$TD3" 待办 >/dev/null
  assert "调度选中高优无依赖的 ${TD3}（${TD2} 被 ${TD1} 阻塞）" bash -c "WF_DAEMON_DRYRUN=1 bash '$SCRIPTS/wf-daemon.sh' once | grep -q '将派发 $TD3'"
  bash "$SCRIPTS/wf-status.sh" "$TD3" 进行中 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$TD3" 待验收 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$TD3" 完成 >/dev/null
  assert "$TD2 仍被阻塞时选中低优的 $TD1" bash -c "WF_DAEMON_DRYRUN=1 bash '$SCRIPTS/wf-daemon.sh' once | grep -q '将派发 $TD1'"
  bash "$SCRIPTS/wf-status.sh" "$TD1" 进行中 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$TD1" 待验收 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$TD1" 完成 >/dev/null
  assert "前置 $TD1 完成后 $TD2 解除阻塞" bash -c "WF_DAEMON_DRYRUN=1 bash '$SCRIPTS/wf-daemon.sh' once | grep -q '将派发 $TD2'"
  bash "$SCRIPTS/wf-status.sh" "$TD2" 进行中 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$TD2" 待验收 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$TD2" 完成 >/dev/null

  # 7.9 暂停检测（D-0007）：mock orca，验证活动检测与恢复路径
  mkdir -p mockbin
  cat > mockbin/orca << 'MOCK'
#!/usr/bin/env bash
now_ms=$(( $(date +%s) * 1000 ))
case "$1 $2" in
  "worktree show")
    case "$4" in
      id:repo::/gone) echo '{"ok":false,"error":"worktree not found"}' >&2; exit 1;;
      *) echo '{"ok":true,"result":{}}'; exit 0;;
    esac;;
  "terminal list")
    case "$4" in
      id:repo::/disconnected) echo '{"result":{"terminals":[{"connected": false, "lastOutputAt": null}]}}';;
      id:repo::/stale) echo "{\"result\":{\"terminals\":[{\"connected\": true, \"lastOutputAt\": $(( now_ms - 7200000 ))}]}}";;
      *) echo "{\"result\":{\"terminals\":[{\"connected\": true, \"lastOutputAt\": $now_ms}]}}";;
    esac
    exit 0;;
esac
exit 0
MOCK
  chmod +x mockbin/orca

  TP1=$(bash "$SCRIPTS/wf-new.sh" task "worktree被删")
  TP2=$(bash "$SCRIPTS/wf-new.sh" task "终端全断开")
  TP3=$(bash "$SCRIPTS/wf-new.sh" task "输出停滞")
  TP4=$(bash "$SCRIPTS/wf-new.sh" task "正常工作")
  for tp in $TP1 $TP2 $TP3 $TP4; do
    bash "$SCRIPTS/wf-status.sh" "$tp" 待办 >/dev/null
    bash "$SCRIPTS/wf-status.sh" "$tp" 进行中 >/dev/null
  done
  sed -i '' 's/^worktree:.*/worktree: repo::\/gone/' docs/tasks/$TP1-*.md
  sed -i '' 's/^worktree:.*/worktree: repo::\/disconnected/' docs/tasks/$TP2-*.md
  sed -i '' 's/^worktree:.*/worktree: repo::\/stale/' docs/tasks/$TP3-*.md
  sed -i '' 's/^worktree:.*/worktree: repo::\/active/' docs/tasks/$TP4-*.md
  PATH="$dir/mockbin:$PATH" bash "$SCRIPTS/wf-daemon.sh" once >/dev/null
  assert_grep "$TP1 worktree 消失 → 暂停" "status: 暂停" docs/tasks/$TP1-*.md
  assert_grep "$TP2 终端全断开 → 暂停" "status: 暂停" docs/tasks/$TP2-*.md
  assert_grep "$TP3 无输出超时 → 暂停" "status: 暂停" docs/tasks/$TP3-*.md
  assert_grep "$TP4 正常输出 → 保持进行中" "status: 进行中" docs/tasks/$TP4-*.md
  assert_grep "$TP1 暂停记录含 worktree 消失原因" "worktree 不存在" docs/tasks/$TP1-*.md
  assert_grep "$TP3 暂停记录含停滞原因" "无输出" docs/tasks/$TP3-*.md
  assert "INDEX 有 ${TP1} 暂停事件" bash -c "grep '$TP1' docs/INDEX.md | grep -q '暂停'"
  bash "$SCRIPTS/wf-status.sh" "$TP1" 进行中 "恢复执行" >/dev/null
  assert_grep "$TP1 暂停→进行中（恢复）" "status: 进行中" docs/tasks/$TP1-*.md
  bash "$SCRIPTS/wf-status.sh" "$TP2" 待办 "重新排队" >/dev/null
  assert "重新排队的 $TP2 会被调度器选中" bash -c "PATH='$dir/mockbin:'\"$PATH\" WF_DAEMON_DRYRUN=1 bash '$SCRIPTS/wf-daemon.sh' once | grep -q '将派发 $TP2'"
  if bash "$SCRIPTS/wf-status.sh" "$TP2" 暂停 >/dev/null 2>&1; then bad "待办→暂停被拒绝"; else ok "待办→暂停被拒绝"; fi
  bash "$SCRIPTS/wf-status.sh" "$TP1" 已废弃 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$TP2" 已废弃 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$TP3" 已废弃 >/dev/null
  bash "$SCRIPTS/wf-status.sh" "$TP4" 已废弃 >/dev/null

  # 8. 归档：终态文件进 _archive，活跃文件不动，ID 引用不断链
  bash "$SCRIPTS/wf-archive.sh" >/dev/null
  assert "终态任务已归档" bash -c "ls docs/tasks/_archive/$MONTH/T-*.md >/dev/null 2>&1"
  assert "被取代决策 $D1 已归档" bash -c "ls docs/decisions/_archive/$MONTH/$D1-*.md >/dev/null 2>&1"
  assert "未取代决策 $D2 不归档" bash -c "ls docs/decisions/$D2-*.md >/dev/null 2>&1"
  assert "活跃问题（待办）不归档" bash -c "ls docs/issues/I-*.md >/dev/null 2>&1"
  assert "已升级 backlog 已归档" bash -c "ls docs/backlog/_archive/$MONTH/$B1-*.md >/dev/null 2>&1"

  # 8.5 归档后仍可查询：wf-query 退到 _archive 并标注已归档，wf-list 不再列出
  assert "wf-query 归档记录标注已归档" bash -c "bash '$SCRIPTS/wf-query.sh' '$T1' | grep -q '已归档'"
  assert "wf-list 不列出已归档记录" bash -c "! bash '$SCRIPTS/wf-list.sh' task | grep -q '$T1'"

  # 全局一致性校验（frontmatter / ID 唯一 / 引用可解析 / INDEX 格式）
  assert "wf-check 全部通过" bash "$SCRIPTS/wf-check.sh"
  echo ""
}

rm -rf "$RUN"
mkdir -p "$RUN"

run_domain "domain-a-script" script
run_domain "domain-b-docs" docs

# 全局：orch 子技能（/orch 调度长官模式）打包正确
assert "orch 子技能文件存在且命名为 orch" bash -c "grep -qx 'name: orch' '$REPO/orch/SKILL.md'"
assert "标题含斜杠时文件名安全（D-0008 修复）" bash -c "cd '$RUN/domain-a-script' && T=\$(bash '$SCRIPTS/wf-new.sh' issue 'a/b 问题') && ls docs/issues/\$T-*.md >/dev/null 2>&1"

echo "=============================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
