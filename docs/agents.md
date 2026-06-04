---
layout: default
title: Agents
nav_order: 3
render_with_liquid: false
---

# Agents

The skill coordinates two groups of agents: custom agents owned and distributed with this plugin, and agents from the `pr-review-toolkit` plugin (an external dependency).

## Full run roster

| Agent | Model | Purpose | When it runs | Context |
|-------|-------|---------|--------------|---------|
| **pr-summarizer** | Sonnet | Summary, walkthrough table, effort score | Always | Manifest + selective reads ¹ |
| **code-reviewer** ² | Sonnet | Tactical bugs, style violations, project conventions | Always | Full diff |
| **architecture-reviewer** | Opus | System design, coupling, API design, technical debt | Full run only | Manifest + selective reads ¹ |
| **security-reviewer** | Opus | OWASP-class security analysis, language-specific checks | Full run only | Manifest + selective reads ¹ |
| **silent-failure-hunter** ² | — | Silent failures, inadequate error handling | If diff has error-handling patterns | Relevant file slices |
| **pr-test-analyzer** ² | — | Test coverage gaps | If test files appear in the diff | Relevant file slices |
| **comment-analyzer** ² | — | Comment accuracy and rot | Full run only, if diff adds/modifies comments | Relevant file slices |
| **type-design-analyzer** ² | — | Type/struct/interface invariants | Full run only, if diff adds type definitions | Relevant file slices |
| **blind-hunter** | Sonnet | Context-free "fresh eyes" review: catches issues familiarity blinds other agents to | Full run only | Raw diff only (no project context) |
| **edge-case-hunter** | Sonnet | Mechanical path tracing: missing else/default, unguarded inputs, off-by-one, overflow, race conditions, resource leaks | Full run only | Manifest + selective reads ¹ |
| **adversarial-general** | Opus | Completeness gaps, missing defenses, operational blindness, documentation debt | Full run only; skipped in TIER=tiny | Manifest + selective reads ¹ |
| **issue-linker** | Haiku | Finds referenced issues and related PRs/issues (GitHub only) | Full run only; skipped in `--pr` and on non-GitHub repos | Commit log + branch + manifest |

¹ For small diffs (under 300 lines), the full diff is passed inline instead.  
² From the `pr-review-toolkit@claude-plugins-official` plugin.

Opus agents (`architecture-reviewer`, `security-reviewer`) use the `opus` alias, which Claude Code resolves to the current Opus model at spawn time. In `--depth deep` mode, `blind-hunter` and `edge-case-hunter` also run on Opus.

## Quick mode roster

`--quick` skips the two Opus agents, both BMAD-inspired agents, and the lower-value conditional agents:

| Agent | Status in `--quick` |
|-------|---------------------|
| pr-summarizer | Runs |
| code-reviewer | Runs |
| silent-failure-hunter | Conditional (if error patterns present) |
| pr-test-analyzer | Conditional (if test files present) |
| architecture-reviewer | **Skipped** |
| security-reviewer | **Skipped** |
| blind-hunter | **Skipped** |
| edge-case-hunter | **Skipped** |
| comment-analyzer | **Skipped** |
| type-design-analyzer | **Skipped** |
| issue-linker | **Skipped** |

## TIER=tiny roster (auto)

Automatically applied when the diff is under 50 lines AND ≤3 files:

| Agent | Status in TIER=tiny |
|-------|---------------------|
| pr-summarizer | Runs (on **Haiku**) |
| code-reviewer | Runs |
| silent-failure-hunter | Conditional |
| pr-test-analyzer | Conditional |
| architecture-reviewer | Conditional — only if infra/CI paths in diff |
| security-reviewer | Conditional — only if auth/credential/dep-manifest paths in diff |
| blind-hunter | **Skipped** |
| edge-case-hunter | **Skipped** |
| comment-analyzer | **Skipped** |
| type-design-analyzer | **Skipped** |
| issue-linker | **Skipped** |

## Agent scope boundaries

Scope boundaries prevent duplicate analysis and token waste across agents:

- **security-reviewer** owns security implications of dependencies; **architecture-reviewer** owns architectural implications
- **security-reviewer** does not report error handling quality — that belongs to **silent-failure-hunter**
- **architecture-reviewer** focuses on structural maintainability, not code-level style — that belongs to **code-reviewer**
- **blind-hunter** receives zero project context by design — it is orthogonal to all other agents. Overlap is expected and handled by deduplication. Do not try to scope-limit it: the independent perspective is the point.
- **edge-case-hunter** asks "does a handling path exist?"; **silent-failure-hunter** asks "is the existing error handling adequate?" — these are distinct questions with minimal overlap. **edge-case-hunter** does not report security implications of gaps (that's **security-reviewer**'s domain).
- **adversarial-general** covers completeness, operational readiness, documentation debt, and deployment/rollback concerns. It does not duplicate what specialist agents cover.

## Symbol context enrichment

On all full runs except TIER=tiny (<50 lines, ≤3 files), the skill automatically extracts symbol references from the diff and looks up their definitions across the repo using Claude Code's `Grep` tool (backed by ripgrep). The results are injected as a `<symbol-context>` block into eligible agents.

**Agents that receive symbol context:** architecture-reviewer, security-reviewer, adversarial-general, edge-case-hunter, code-reviewer.  
**Agents excluded:** blind-hunter (zero-context constraint), pr-summarizer (does not need definitions), all pr-review-toolkit agents (externally managed).

Use `--no-enrich-context` to disable. Enrichment adds ~1–3K tokens per eligible agent (~8–16K total on a full run).

## PR narrative

Phase 0 builds a `PR_NARRATIVE` block from full commit bodies and (in `--pr <N>` mode) the PR description body. This is passed to most agents to reduce false positives where agents flag changes the author has already explained. **blind-hunter is excluded** to preserve its zero-context constraint.

## Confidence filtering

All custom agents emit a `confidence` integer (0–100) per finding. The `--min-confidence` flag (default: 75) filters out low-confidence findings before suppression rules are applied.

| Range | Meaning |
|-------|---------|
| 91–100 | Certain — reproducible problem, no context needed |
| 76–90 | High — strong evidence, minor ambiguity |
| 51–75 | Moderate — plausible but depends on context |
| 26–50 | Low — speculative |
| 0–25 | Very low — hunch or pattern-match |

Lower `--min-confidence` to see more findings; raise it to reduce noise. Use `0` to disable filtering entirely.

## Output contract (`json-findings`)

Each custom findings agent appends a structured JSON block to its output:

````
```json-findings
[{"severity":"High","confidence":85,"category":"injection","file":"path/to/file","line":42,"finding":"description","remediation":"how to fix","source":"agent-name"}]
```
````

This block is consumed by the Phase 2 pipeline for normalization, confidence filtering, suppression, and deduplication. The human-readable markdown section remains for inspection; the `json-findings` block drives the structured pipeline.
