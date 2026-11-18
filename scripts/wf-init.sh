#!/usr/bin/env bash
# wf-init.sh — 初始化 docs/ 记录结构（幂等）
set -euo pipefail
source "$(dirname "$0")/wf-common.sh"
SKILL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$WF_DOCS"/{decisions,tasks,issues,backlog,logs}

for t in decisions tasks issues backlog; do
  [ -f "$WF_DOCS/$t/_template.md" ] || cp "$SKILL_ROOT/assets/templates/$t/_template.md" "$WF_DOCS/$t/_template.md"
done
[ -f "$WF_DOCS/README.md" ] || cp "$SKILL_ROOT/assets/README.md" "$WF_DOCS/README.md"
if [ ! -f "$WF_DOCS/INDEX.md" ]; then
  cp "$SKILL_ROOT/assets/INDEX.md" "$WF_DOCS/INDEX.md"
  wf_index "docs/" "初始化目录结构与模板" "wf-init"
fi

echo "wf-init: 就绪 → $WF_DOCS/"
