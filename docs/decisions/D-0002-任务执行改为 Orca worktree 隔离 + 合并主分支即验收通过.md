---
id: D-0002
type: decision
status: 完成
created: 2026-11-20
source: PRD
superseded_by:
---

# 任务执行改为 Orca worktree 隔离 + 合并主分支即验收通过

## 决策内容

任务进入执行时，用 `orca worktree create` 为该任务创建独立 worktree（命名 `T-xxxx-简短描述`），任务文件 frontmatter 记录 worktree id 与分支名；任务的结果层面验收标准改为"该分支合并回主分支"——合并成功即结果层面验收通过，日志层面标准不变。

## 背景与理由

1. 任务并行执行时在同一 checkout 里互相污染，worktree 提供文件系统级隔离
2. "完成"需要客观判据：分支合并进主分支是可机械验证的信号，替代模糊的"看起来做完了"
3. Orca 管理 worktree 的生命周期与终端，比裸 `git worktree` 多一层可查询的状态（`orca worktree ps/list`）

## 影响范围

- SKILL.md 工作方式：建任务、验收两步的行为
- assets/README.md：新增"任务执行环境"机制，修改验收特殊规则
- assets/templates/tasks/_template.md：frontmatter 增加 worktree/branch 字段

