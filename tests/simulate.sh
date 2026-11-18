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

  # 3. 任务（带双层验收标准）
  T1=$(bash "$SCRIPTS/wf-new.sh" task "实现核心功能" --source PRD)
  assert_grep "任务 $T1 初始状态待办" "status: 待办" docs/tasks/$T1-*.md
  assert_grep "任务 $T1 验收标准含结果层面" "结果层面" docs/tasks/$T1-*.md
  assert_grep "任务 $T1 验收标准含日志层面" "日志层面" docs/tasks/$T1-*.md

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

echo "=============================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
