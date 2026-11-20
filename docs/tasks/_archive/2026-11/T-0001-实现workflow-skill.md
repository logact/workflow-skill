---
id: T-0001
type: task
status: 完成
created: 2026-11-18
source: PRD
priority: 中
depends_on:
---

# 实现 workflow-skill（建模任务）

## 目标
根据 docs/PRD.md 实现本 skill，使任意项目能通过它落地 PRD 描述的记录工作流：
结构初始化、对话中识别并记录任务/决策/问题/backlog、状态流转、验收循环（无死端）、归档。
文件结构与状态规则以 docs/README.md 为准。

## 验收标准

### 结果层面（能跑一遍、能看产出）
- [x] 构造至少 2 个不同类型的测试 domain（fixture 项目，如一个脚本项目、一个文档项目），互不依赖
- [x] 在每个测试 domain 中完整模拟 PRD 场景流程并全部通过：
  1. 初始化结构（decisions/tasks/issues/backlog/INDEX/README）
  2. 对话中识别决策点并记录 D-xxxx（含一次决策变更：新决策 + 旧决策 superseded_by）
  3. 创建任务（带双层验收标准）
  4. 记录问题（一个问题一个文件）
  5. 模拟多 agent 并行处理问题：各写各的文件，INDEX 只追加，无写冲突
  6. 验收通过 → 状态流转到完成；验收不通过 → 新建问题文件 → 回到处理（无死端）
  7. backlog 回流：条目升级为任务
  8. 归档：终态文件移入 _archive/YYYY-MM/，ID 引用不断链
- [x] 模拟产出符合 docs/README.md 全部规则（frontmatter 状态合法、ID 引用、INDEX 事件格式）
- [x] 以上模拟有可复现的执行方式（脚本或固定操作序列），一个月后能重跑

### 日志层面（人工可审核）
- [x] docs/logs/ 有开发过程记录
- [x] 每个测试 domain 的模拟过程有可审核的输出记录（模拟日志或 INDEX 事件流）

## 实现产物（2026-11-18）
- SKILL.md：skill 入口与 agent 行为准则
- scripts/：wf-init / wf-new / wf-status / wf-archive / wf-check（+ wf-common 公共库），bash，无依赖
- assets/：README、INDEX、四类模板（wf-init 拷贝源）
- tests/simulate.sh：双 domain（script 项目 + 文档项目）全流程模拟，46 项断言

## 验收方式
- 机械层：`bash tests/simulate.sh`，输出 `PASS=46 FAIL=0`；事件流见 tests/run/*/docs/INDEX.md
- 人类层（第一轮验收意见后补充）：`bash tests/demo.sh`，11 步交互式叙事演示，逐步人审

## 验收记录
- 2026-11-18 第一轮：验收不通过。用户意见"机械测试通过对人类验证意义不大" → 记 I-0001，任务打回进行中
- 2026-11-18 第二轮：**通过**（用户明确"验收通过"）。人类验收走 tests/demo.sh；机械层 simulate.sh 46/46 可复现
