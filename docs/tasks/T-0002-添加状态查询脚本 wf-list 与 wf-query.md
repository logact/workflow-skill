---
id: T-0002
type: task
status: 完成
created: 2026-11-18
source: PRD

---

# 添加状态查询脚本 wf-list 与 wf-query

## 目标
当前脚本只有写入/流转/归档/校验，没有查询入口，查状态只能翻 INDEX 或逐个读 frontmatter。新增两个只读脚本：
- `wf-list.sh [类型] [状态]`：列出某类型/某状态（缺省为全部活跃）的记录，输出 `ID | 状态 | 标题`
- `wf-query.sh <ID>`：打印单个记录的当前状态与所属文件，并附 INDEX 中该 ID 的全部事件历史

## 验收标准
- [ ] 结果层面：在测试 domain 中 `wf-list.sh` 能按类型/状态过滤列出记录，`wf-query.sh` 能输出指定 ID 的当前状态与完整事件历史；`bash tests/simulate.sh` 全绿
- [ ] 日志层面：docs/logs/ 中有对应记录

## 验收记录
- 2026-11-18 通过（用户直接标记通过；人工未实际验证，依据仅为 tests/simulate.sh 机械模拟 64 项全绿）

