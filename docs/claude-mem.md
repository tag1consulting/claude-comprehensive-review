---
layout: default
title: claude-mem Integration
nav_order: 9
render_with_liquid: false
---

# claude-mem Integration

If [claude-mem](https://github.com/thedotmack/claude-mem) is installed and its worker daemon is running, the skill automatically integrates with it to provide persistent cross-session review memory.

## What it does

1. **Detects** the worker daemon via health check (`GET http://127.0.0.1:<MEM_PORT>/api/health`) in Phase 0
2. **Retrieves** up to 5 prior review summaries for the same project and passes them as a `PRIOR_REVIEW_CONTEXT` block (~500 tokens) to `architecture-reviewer` and `security-reviewer`
3. **Stores** a compact structured review summary after each run (project slug, branch, findings counts, top 3 findings, agents run)

## Enabling and disabling

Integration is **automatic with opt-out**. No configuration needed. Use `--no-mem` to opt out for a specific run:

```
/comprehensive-review --no-mem
```

If claude-mem is not running, detection fails silently and the feature is disabled for that run.

## Agent access

Only `architecture-reviewer` and `security-reviewer` receive prior review context. `blind-hunter`'s zero-context constraint is preserved — it never receives prior context.

## Token economics

| Operation | Token cost |
|-----------|-----------|
| Detection (health check) | ~0 (Bash, no LLM tokens) |
| Prior review search (5 results) | ~250–500 tokens |
| `PRIOR_REVIEW_CONTEXT` passed to 2 agents | ~500 tokens max |
| Summary storage (curl POST) | ~0 (Bash, no LLM tokens) |
| **Total overhead per run** | **~750–1,000 tokens** |

Break-even: if prior-review context helps architecture-reviewer or security-reviewer skip ~1,000 tokens of re-analysis on a recurring pattern, the integration pays for itself. On a typical full run (50K–200K tokens), this is a rounding error. The value is qualitative: recurring issues are more likely to be flagged as patterns rather than isolated findings.

## Security note

> Review summaries including finding descriptions are stored in claude-mem's local SQLite database, accessible to any process on localhost without authentication. Avoid using this integration in shared or multi-tenant environments.
{: .warning }

## Implementation notes

- All claude-mem interactions (health check, search, save) fail silently — any failure degrades gracefully with no impact on the review
- Subagents cannot access MCP tools; all claude-mem interaction happens in the orchestrator
- MCP search tools are used for retrieval; HTTP API is used for writing (no write MCP tool is currently available in claude-mem)
