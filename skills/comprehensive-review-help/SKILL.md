---
name: comprehensive-review-help
description: "Show help for the /comprehensive-review skill"
disable-model-invocation: true
---

!`cat "${CLAUDE_SKILL_DIR}/../comprehensive-review/HELP.md" 2>/dev/null || echo "Help file not found. Run /plugins install comprehensive-review@tag1consulting to reinstall."`
