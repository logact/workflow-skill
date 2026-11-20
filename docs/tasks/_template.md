---
id: T-xxxx
type: task
status: 待办
created: YYYY-MM-DD
source: PRD            # 来源：I-xxxx 或 PRD（用 ID 引用，不写路径）
worktree:              # orca worktree id（<repoId>::<path>），执行时创建
branch:                # 对应 git 分支名
---

# 任务标题

## 目标
做什么、为什么做。

## 验收标准
- [ ] 结果层面：worktree 分支合并回主分支（合并提交存在即通过）
- [ ] 日志层面：docs/logs/ 中有对应记录

## 验收记录
- YYYY-MM-DD 通过 / 不通过（不通过 → 新建问题 I-xxxx）
