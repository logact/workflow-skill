# docs/ — 工作流文件结构与状态管理

本目录是项目所有过程记录的根。规则源于 `docs/PRD.md`，任何修改需走 PRD 变更复查机制。

## 目录结构（类型 = 目录）

```
docs/
├── README.md        # 本文件
├── PRD.md           # 产品需求，唯一，变更走复查机制
├── INDEX.md         # 共享索引，只追加事件，不回改
├── decisions/       # 决策记录，前缀 D-
├── tasks/           # 任务（每个必须带验收标准），前缀 T-
├── issues/          # 问题（一个问题一个文件），前缀 I-
├── backlog/         # 搁置条目，前缀 B-
└── logs/            # 过程日志（按日期一天一个文件）
```

命名：`T-0001-简短描述.md`，序号全局递增不回收。每个目录下的 `_template.md` 是对应类型的模板。

## 状态管理

状态写在文件 frontmatter 的 `status` 字段，**这是唯一事实源**。不用状态子目录移动文件——移动会打断追溯链里的相对链接。

状态集合：`待办 / 进行中 / 待验收 / 完成 / 已搁置 / 已废弃`

```
待办 → 进行中 → 待验收 → 完成
                  ↓ 验收不通过
        新建 issues/I-xxxx 记录问题，本任务回到"进行中"
任何状态 → 已搁置（等 backlog 回流扫描）/ 已废弃（必须写原因）
```

特殊规则：

1. **决策不改写**：决策变更时新建 D-xxxx，旧决策 frontmatter 加 `superseded_by: D-xxxx`
2. **并行约束**：多个 agent 同时工作时只写自己的问题/任务文件；`INDEX.md` 只追加，格式：
   `YYYY-MM-DD HH:MM | 文件ID | 事件 | 操作者`
3. **追溯链**：文件间引用一律用全局唯一 ID（如 `I-0003`），不写相对路径——这样归档移动文件也不会断链；定位文件用 grep ID
4. **任务执行环境（Orca worktree，见 decisions/D-0002）**：任务进入执行时，用 `orca worktree create --name T-xxxx-简短描述 --json` 创建独立 worktree，把返回的 worktree id（`<repoId>::<path>`）和分支名写进任务文件 frontmatter 的 `worktree`/`branch` 字段；执行 agent 在该 worktree 内工作，互不污染
5. **验收**：每个任务的结果层面标准是"worktree 分支合并回主分支"——合并提交存在即通过；日志层面标准是 docs/logs/ 有记录。两层都过才算验收通过
6. **backlog 回流**：每轮验收后扫一遍 backlog/，决定哪些升级为任务
7. **记录即提交（见 decisions/D-0003）**：记录的每次创建/修改必须进 git。`wf-new.sh`/`wf-status.sh`/`wf-archive.sh` 会自动 `git add` 本次涉及的文件（记录文件 + INDEX.md）并提交，提交信息格式 `wf: <动作> <ID>`；脚本之外的手工修改（如补全验收标准、填写决策正文）由 agent 改完立即自行提交。非 git 仓库或被 gitignore 的路径（如 tests/ 演示工作区）自动跳过

## 归档机制（见 decisions/D-0001）

文件积压时归档终态文件，规则：

1. **归档位置**：各类型目录下的 `_archive/YYYY-MM/`，如 `tasks/_archive/2026-11/T-0001-xxx.md`
2. **归档时机**：每轮验收结束后执行，和 backlog 回流扫描（机制6）同一时机；只对终态文件（完成/已废弃/已取代的决策）归档，活跃文件（待办/进行中/待验收）不动
3. **决策例外**：未被取代的决策永不归档——数量少，且需要随时对照；被取代的可归档
4. **永不归档**：`README.md`、`INDEX.md`、`PRD.md`（INDEX 是回放历史的唯一入口，纯文本追加成本极低）
5. **归档动作**：移动文件 + INDEX.md 追加一行 `文件ID | 归档 → _archive/YYYY-MM | 操作者`，无其他改动
6. 下划线前缀让 `_archive` 在列表中排在最后且一眼可辨；如需恢复活跃，直接移回上级目录并追加 INDEX 事件

查看当前状态分布：用 `scripts/wf-list.sh`（按类型/状态过滤列出活跃记录）和 `scripts/wf-query.sh <ID>`（单条记录的状态 + INDEX 事件历史，已归档的也能查），不手工维护视图。
