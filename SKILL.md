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
| `wf-new.sh <decision\|task\|issue\|backlog> <标题> [--source ID\|PRD] [--supersedes D-xxxx]` | 创建记录，自动分配全局递增 ID，追加 INDEX |
| `wf-status.sh <ID> <新状态> [备注]` | 状态流转（校验合法性，非法流转拒绝），追加 INDEX |
| `wf-list.sh [decision\|task\|issue\|backlog] [状态]` | 列出活跃记录的 `ID \| 状态 \| 标题`（只读；归档记录不在列） |
| `wf-query.sh <ID>` | 查询单个记录的当前状态、所属文件与 INDEX 全部事件历史（只读；已归档的也能查，会标注） |
| `wf-archive.sh` | 归档终态文件到 `_archive/YYYY-MM/`（未取代的决策、INDEX/README/PRD 永不归档） |
| `wf-check.sh` | 校验：frontmatter 合法、ID 无重复、ID 引用可解析、INDEX 格式正确 |

## 状态机

```
待办 → 进行中 → 待验收 → 完成
                  ↓ 验收不通过（新建 issue，本任务回到"进行中"）
任何活跃状态 → 已搁置 / 已废弃；已搁置 → 待办（回流）/ 完成（已升级）
```

## 工作方式（agent 行为准则）

1. **初始化**：项目首次使用，先跑 `wf-init.sh`
2. **记录决策**：识别到"选了 A 放弃 B"的时刻 → 提议一句话 → 确认后 `wf-new.sh decision`；决策变更用 `--supersedes` 取代旧决策，不改写旧文件
3. **建任务**：`wf-new.sh task`，创建时必须在文件里补全双层验收标准；进入执行时用 `orca worktree create --name T-xxxx-简短描述 --json` 建独立 worktree，把 worktree id 和分支名写进任务文件 frontmatter，执行 agent 在该 worktree 内工作
4. **记问题**：`wf-new.sh issue`，一个问题一个文件；多个问题可并行交给多个 agent，各写各的
5. **验收**：结果层面看 worktree 分支是否合并回主分支（合并成功即通过）+ 日志层面查记录，通过 → `wf-status.sh T-xxxx 完成`；不通过 → `wf-new.sh issue` + `wf-status.sh T-xxxx 进行中`
6. **每轮验收后**：扫 backlog/ 决定回流；跑 `wf-check.sh` 确认一致性。**不归档**——`wf-archive.sh` 只在用户明确要求时执行（D-0004）
7. **修改规则**：结构或流程的改动必须改 assets/README.md 并记录决策文件

详细规则见 assets/README.md（初始化后即在项目 docs/README.md）。
