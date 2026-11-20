---
name: workflow
description: PRD 驱动的项目记录工作流。在对话中识别并记录决策/任务/问题/backlog，管理状态流转、验收循环（无死端）、归档。当用户要求初始化记录结构、记录决策、创建任务、记录问题、验收任务、回流 backlog 或归档时使用。
---

# workflow — 记录工作流

把"决策有记录、记录不混乱、任务可验收"落成文件系统约定 + 确定性脚本。agent 负责记录，用户只负责确认（最小摩擦）。

## 核心原则（不可违背）

1. 每个决策都要有记录：对话中识别到决策点，**主动提议一句话记录**，用户确认后执行 `wf-new.sh decision`
2. 一个文件一个归属：一个问题/任务/决策一个文件；多 agent 并行时只写自己的文件，INDEX 只追加
3. 状态唯一事实源是文件 frontmatter 的 `status` 字段；文件间引用一律用 ID（如 `I-0003`），不写相对路径
4. 每个任务必须带双层验收标准：结果层面（worktree 分支合并回主分支）+ 日志层面（docs/logs/ 有记录）
5. 验收不通过没有死端：新建问题文件，任务回到"进行中"，循环继续
6. 记录即提交：记录的每次创建/修改必须进 git。`wf-new.sh`/`wf-status.sh`/`wf-archive.sh` 会自动提交本次涉及的文件；脚本之外的手工修改由 agent 改完立即自行提交

## 脚本（scripts/，bash，无依赖）

所有脚本在项目根目录执行，操作 `./docs/`（可用环境变量 `WF_DOCS` 覆盖）。

| 命令 | 作用 |
|---|---|
| `wf-init.sh` | 初始化 docs/ 结构（幂等），拷贝 README/INDEX/模板 |
| `wf-new.sh <decision\|task\|issue\|backlog> <标题> [--source ID\|PRD] [--supersedes D-xxxx] [--priority 高\|中\|低] [--depends-on T-xxxx,...]` | 创建记录，自动分配全局递增 ID，追加 INDEX（`--priority`/`--depends-on` 仅 task） |
| `wf-status.sh <ID> <新状态> [备注]` | 状态流转（校验合法性，非法流转拒绝），追加 INDEX |
| `wf-list.sh [decision\|task\|issue\|backlog] [状态]` | 列出活跃记录的 `ID \| 状态 \| 标题`（只读；归档记录不在列） |
| `wf-query.sh <ID>` | 查询单个记录的当前状态、所属文件与 INDEX 全部事件历史（只读；已归档的也能查，会标注） |
| `wf-daemon.sh <once\|start [--interval N]\|stop\|status>` | 守护调度器：派发"待办且前置全部完成"的最高优先级任务到 Orca worktree；检查进行中任务的分支合并（已合并自动转待验收）与执行中断（agent 自我报告 + 活动检测兜底：worktree 消失/终端全断开/无输出超时，自动转暂停并记录原因） |
| `wf-archive.sh` | 归档终态文件到 `_archive/YYYY-MM/`（仅用户明确要求时执行） |
| `wf-check.sh` | 校验：frontmatter 合法、ID 无重复、ID 引用可解析、INDEX 格式正确 |

## 命令

- `/orch`：调度长官模式（见 orch/SKILL.md，D-0008）。当前 agent 成为调度长官：启动 `wf-daemon.sh` 守护线程，作为所有任务/issue 创建的唯一入口，负责审批流转、队列监控、暂停与待验收的收口；不亲自写代码。说"退出调度"停止守护线程下岗

## 状态机

```
起草 → 待办 → 进行中 → 待验收 → 完成
                ↓ ↑
              暂停（守护器检测到执行中断自动转入并记录原因；
                   恢复 → 进行中，或转待办重新派发）
                  ↓ 验收不通过（新建 issue，本任务回到"进行中"）
任何活跃状态 → 已搁置 / 已废弃；已搁置 → 待办（回流）/ 完成（已升级）
```

"起草"是可执行队列的闸门：任务创建即起草，用户审批转"待办"后才可能被调度器执行（D-0006）。"暂停"是执行中断的停泊点：执行 agent 遇到阻塞应自我报告转暂停；守护器活动检测兜底——worktree 消失、终端全断开或终端超过阈值无输出（`WF_DAEMON_STALL_MINUTES`，默认 30 分钟）时自动转暂停并记录原因（D-0007），恢复方式由用户决定。

## 工作方式（agent 行为准则）

1. **初始化**：项目首次使用，先跑 `wf-init.sh`
2. **记录决策**：识别到"选了 A 放弃 B"的时刻 → 提议一句话 → 确认后 `wf-new.sh decision`；决策变更用 `--supersedes` 取代旧决策，不改写旧文件
3. **建任务**：`wf-new.sh task`（可带 `--priority`/`--depends-on`），创建时必须在文件里补全双层验收标准；新任务处于"起草"，用户审批 `wf-status.sh T-xxxx 待办` 后才进可执行队列
4. **记问题**：`wf-new.sh issue`，一个问题一个文件；多个问题可并行交给多个 agent，各写各的
5. **执行任务**：优先用 `wf-daemon.sh start` 启动守护调度（或 `once` 手动跑一趟）——自动把"待办且前置全部完成"的最高优先级任务派发到 Orca worktree（D-0002/D-0005）；分支合并回主分支后守护器自动转"待验收"。手工执行时用 `orca worktree create --name T-xxxx-简短描述 --json` 建独立 worktree，把 worktree id 和分支名写进任务文件 frontmatter
6. **验收**：结果层面看 worktree 分支是否合并回主分支（合并成功即通过）+ 日志层面查记录，通过 → `wf-status.sh T-xxxx 完成`；不通过 → `wf-new.sh issue` + `wf-status.sh T-xxxx 进行中`
7. **每轮验收后**：扫 backlog/ 决定回流；跑 `wf-check.sh` 确认一致性。**不归档**——`wf-archive.sh` 只在用户明确要求时执行（D-0004）
8. **修改规则**：结构或流程的改动必须改 assets/README.md 并记录决策文件

详细规则见 assets/README.md（初始化后即在项目 docs/README.md）。
