#!/usr/bin/env bash
# tests/demo.sh — 交互式演示：把 PRD 流程场景演给人看
# 用法: bash tests/demo.sh    每步按回车继续，Ctrl-C 随时中止
# 工作区在 tests/demo/，演示后保留供翻看
set -uo pipefail
export LC_ALL=en_US.UTF-8   # bash 3.2 + C locale 会把多字节首字节并入变量名

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$REPO/scripts"
WS="$REPO/tests/demo"

step=0
next()  { step=$((step+1)); printf '\n\033[1m════════ 第 %s 步｜%s ════════\033[0m\n' "$step" "$1"; }
say()   { printf '%s\n' "$1"; }
pause() { printf '\n—— 按回车继续（Ctrl-C 中止）——'; read -r _ || true; }
run()   { printf '\n$ %s\n' "$*"; "$@"; }
show()  { printf '\n--- %s ---\n' "$1"; cat "$1"; }

rm -rf "$WS"; mkdir -p "$WS"; cd "$WS" || exit 1
printf '#!/usr/bin/env bash\necho hello\n' > main.sh

say "这是 workflow-skill 的交互式演示。"
say "我会扮演 agent，在一个模拟项目里边做边讲 PRD 的完整流程，"
say "每一步都会展示真实产生的文件，你判断是否符合直觉。"
pause

# ── 1 ─────────────────────────────────────────────
next "初始化：空项目接入工作流"
say "项目里现在只有一个 main.sh。agent 第一次接入时跑 wf-init："
run bash "$SCRIPTS/wf-init.sh"
say "生成了 docs/ 结构：decisions(决策) tasks(任务) issues(问题) backlog(搁置) + INDEX(事件流)。"
run find docs -type f
pause

# ── 2 ─────────────────────────────────────────────
next "记录决策：对话中识别到决策点"
say "你说：'记录就用 JSON 文件存吧'。agent 识别到这是一个决策，提议记录，你确认："
run bash "$SCRIPTS/wf-new.sh" decision "用JSON文件存记录"
show docs/decisions/D-0001-*.md
pause

# ── 3 ─────────────────────────────────────────────
next "决策变更：不改写旧决策，用新决策取代"
say "聊了几轮后你说：'JSON 不好读，还是 Markdown 吧'。"
say "agent 不改写 D-0001，而是新建 D-0002 并取代它（每个决策都要有记录，包括改主意）："
run bash "$SCRIPTS/wf-new.sh" decision "改用Markdown文件存记录" --supersedes D-0001
say "旧决策现在的样子（注意 superseded_by 和 status 两行）："
run head -8 docs/decisions/D-0001-*.md
pause

# ── 4 ─────────────────────────────────────────────
next "创建任务：必须带双层验收标准，创建即'起草'待审批"
say "你说：'开始干活吧'。agent 创建任务，创建时就必须写清怎么算做完："
run bash "$SCRIPTS/wf-new.sh" task "实现记录脚本" --source PRD --priority 高
show docs/tasks/T-0001-*.md
say "注意：新任务状态是'起草'——这是审批门（D-0006），你点头后才进可执行队列："
run bash "$SCRIPTS/wf-status.sh" T-0001 待办 "审批通过"
pause

# ── 5 ─────────────────────────────────────────────
next "记录问题：一个问题一个文件"
say "干活中发现问题，你说：'帮我记一下：输出格式不对'。"
run bash "$SCRIPTS/wf-new.sh" issue "输出格式不对" --source T-0001
show docs/issues/I-0001-*.md
pause

# ── 6 ─────────────────────────────────────────────
next "多 agent 并行：各写各的，INDEX 只追加"
say "你派 3 个 agent 同时研究 3 个问题。现在 3 个进程同时创建文件（机制3：共享索引只能追加）："
bash "$SCRIPTS/wf-new.sh" issue "并行问题A" >/dev/null &
bash "$SCRIPTS/wf-new.sh" issue "并行问题B" >/dev/null &
bash "$SCRIPTS/wf-new.sh" issue "并行问题C" >/dev/null &
wait
say "3 个进程同时跑完，ID 没有撞号，INDEX 没有丢行："
run grep -h '^id:' docs/issues/I-*.md
run grep '创建（并行问题' docs/INDEX.md
pause

# ── 7 ─────────────────────────────────────────────
next "验收通过：状态流转到完成"
say "任务做完了，你验收：跑一遍（结果层面）+ 查日志（日志层面），都过了："
run bash "$SCRIPTS/wf-status.sh" T-0001 进行中
run bash "$SCRIPTS/wf-status.sh" T-0001 待验收
run bash "$SCRIPTS/wf-status.sh" T-0001 完成
pause

# ── 8 ─────────────────────────────────────────────
next "验收不通过：没有死端"
say "下一个任务'修复输出格式'，你验收时发现还有问题。"
say "流程不是卡死，而是：打回进行中 + 派生新的问题文件："
T2=$(bash "$SCRIPTS/wf-new.sh" task "修复输出格式" --source I-0001)
bash "$SCRIPTS/wf-status.sh" "$T2" 待办 "审批通过" >/dev/null
bash "$SCRIPTS/wf-status.sh" "$T2" 进行中 >/dev/null
bash "$SCRIPTS/wf-status.sh" "$T2" 待验收 >/dev/null
run bash "$SCRIPTS/wf-status.sh" "$T2" 进行中 "验收不通过"
run bash "$SCRIPTS/wf-new.sh" issue "修复后仍有边界错误" --source "$T2"
say "修好后第二轮验收通过。另外注意：已完成的任务不允许再被改动（终态）："
bash "$SCRIPTS/wf-status.sh" "$T2" 待验收 >/dev/null
bash "$SCRIPTS/wf-status.sh" "$T2" 完成 >/dev/null
run bash "$SCRIPTS/wf-status.sh" "$T2" 进行中
pause

# ── 9 ─────────────────────────────────────────────
next "backlog 回流：搁置条目升级为任务"
say "之前你说'导出 HTML 先放放'，记进了 backlog。这轮验收后扫一眼，决定现在做："
run bash "$SCRIPTS/wf-new.sh" backlog "支持导出HTML"
T3=$(bash "$SCRIPTS/wf-new.sh" task "实现HTML导出" --source B-0001 --depends-on T-0001)
bash "$SCRIPTS/wf-status.sh" B-0001 完成 "回流后已升级为 $T3" >/dev/null
bash "$SCRIPTS/wf-status.sh" "$T3" 待办 "审批通过" >/dev/null
say "backlog 条目已标记'完成'（使命达成，升级成了 ${T3}），不会变成坟场。"
pause

# ── 9.5 ───────────────────────────────────────────
next "守护调度：自动执行可做的待办任务"
say "启动 wf-daemon 后，它会自动挑'待办且前置全部完成'的最高优先级任务，"
say "派发到 Orca worktree 执行；分支合并回主分支后自动转'待验收'等你验收。"
say "这里用 dryrun 模式展示它的调度决策（不真正派发）："
WF_DAEMON_DRYRUN=1 run bash "$SCRIPTS/wf-daemon.sh" once
pause

# ── 10 ────────────────────────────────────────────
next "归档：用户明确要求时，终态文件沉底"
say "文件积多了，你明确说'归档吧'，agent 才会跑 wf-archive（不会自动归档）："
run bash "$SCRIPTS/wf-archive.sh"
say "归档后的目录（注意 _archive/ 出现在各类型目录内）："
run find docs -type f -name '*.md' | sort
say "未取代的 D-0002、还活跃的问题都没有被归档。"
pause

# ── 11 ────────────────────────────────────────────
next "回放：一个月后回答'这个改动是为了什么'"
say "INDEX 是完整事件流（只追加，无人回改）："
run cat docs/INDEX.md
say ""
say "一致性检查（frontmatter 合法 / ID 无重复 / 引用可解析 / INDEX 格式）："
run bash "$SCRIPTS/wf-check.sh"

printf '\n\033[1m════════ 演示结束 ════════\033[0m\n'
say "工作区保留在 tests/demo/，所有文件可随意翻看。"
say "验收标准：以上每一步是否符合你对这套工作流的预期？"
say "符合 → 告诉我'验收通过'；不符合 → 说出问题，我记录为 issue 进入下一轮循环。"
