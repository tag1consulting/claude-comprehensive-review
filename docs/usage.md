---
layout: default
title: Usage & Flags
nav_order: 2
render_with_liquid: false
---

# Usage & Flags

## Basic usage

Run from any git repository on the branch you want to review:

```
/comprehensive-review [flags]
```

By default, everything runs locally — no PR is created, no remote posting occurs. All posting requires explicit opt-in flags.

## Flags

| Flag | Effect |
|------|--------|
| `--base <branch>` | Compare against a specific base branch (default: auto-detected upstream or `main`) |
| `--quick` | Fast mode: pr-summarizer + code-reviewer + triggered error/test agents only. Skips security, architecture, blind-hunter, edge-case-hunter, comment, and type analysis. Roughly 60–80% cheaper. |
| `--security-only` | Run security-reviewer + CVE check on changed dependency manifests only |
| `--depth <tier>` | Agent depth: `normal` (default) or `deep`. In `deep` mode, blind-hunter and edge-case-hunter run on the `opus` alias, Opus agents use extended step-by-step reasoning, and a CVE reachability triage pass annotates which vulnerabilities are reachable in the diff. |
| `--summary-only` | Run only the pr-summarizer agent |
| `--create-pr` | Create a PR using Block A as the description. Without this flag, no PR is created. |
| `--post-summary` | Post Block A (summary) as a comment on an existing PR/MR |
| `--post-findings` | Post Block B (findings) as inline review on an existing own PR/MR |
| `--no-findings` | Suppress posting findings (useful for dry-run with `--pr`) |
| `--no-post` / `--local` | Explicit alias for the default: display everything locally, skip all remote operations |
| `--pr <number>` | Review an existing PR/MR by number (external review mode) |
| `--provider <name>` | Override auto-detected git provider (`github`, `gitlab`, `bitbucket`) |
| `--no-enrich-context` | Disable symbol context enrichment (Grep-based cross-file definition lookup). Enrichment is on by default for all full runs except TIER=tiny. |
| `--no-mem` | Disable claude-mem integration (auto-detected when available) |
| `--no-suppress` | Disable all suppression rules (useful for debugging / audit runs) |
| `--min-confidence <N>` | Filter findings below this confidence threshold (0–100; default: 75; 0 disables filtering). Applied before suppression rules. |
| `--output-file <path>` | Write Block A + Block B to a markdown file during Phase 5. Saves ~$5–15 on large PRs by avoiding a separate follow-up request. |

## Auto-cheap routing

These modes activate automatically based on diff content — no flags needed:

| Mode | Trigger | What runs |
|------|---------|-----------|
| **TIER=tiny** | Diff is under 50 lines AND ≤3 files | pr-summarizer (Haiku), code-reviewer, triggered conditionals; architecture/security if triggered by infra/security paths; ~$0.30 floor |
| **DOCS_ONLY** | All changed files are docs/markdown/meta (no code or infra) | pr-summarizer + code-reviewer + triggered conditionals; all Opus agents and blind/edge-case/comment/type agents skipped |
| **LOW_RISK_CONFIG** | Diff contains only config/YAML/TOML with no security-sensitive patterns, no dep manifests, no Dockerfile/CI paths | pr-summarizer + code-reviewer + deterministic checks; specialist and blind/edge-case agents skipped |

All auto-cheap modes are reported in Phase 5 output. `--depth deep`, `--quick`, `--security-only`, and `--summary-only` override DOCS_ONLY and LOW_RISK_CONFIG.

## Examples

```bash
# Full review — everything shown locally, no PR created
/comprehensive-review

# Review and create a PR with the summary as its description
/comprehensive-review --create-pr

# Fast review — roughly 60–80% cheaper, skips security and architecture agents
/comprehensive-review --quick

# Review your own open PR and share findings with co-reviewers
/comprehensive-review --post-findings

# Review + post both summary and findings on your own open PR
/comprehensive-review --post-summary --post-findings

# Review someone else's PR #42 locally (no remote posting)
/comprehensive-review --pr 42

# Review PR #42 and post findings as inline review
/comprehensive-review --pr 42 --post-findings

# Review PR #42 and post both summary and findings
/comprehensive-review --pr 42 --post-summary --post-findings

# Review against a non-default base branch
/comprehensive-review --base develop

# Security scan only (includes CVE check on changed dependency manifests)
/comprehensive-review --security-only

# Deep review — Opus for all agents + extended reasoning + CVE reachability triage
/comprehensive-review --depth deep

# Write report to disk (avoids re-running in a fresh session)
/comprehensive-review --output-file ~/reports/my-pr-review.md
```

## Posting behavior

| Scenario | Block A posted? | Block B posted? | Review event |
|----------|----------------|----------------|--------------|
| No PR exists (default) | No | No | N/A |
| No PR exists + `--create-pr` | Yes — PR description | No | N/A |
| No PR exists + `--create-pr --post-findings` | Yes — PR description | Yes — inline review | `COMMENT` |
| Existing own PR (default) | No | No | N/A |
| Existing own PR + `--post-summary` | Yes — PR comment | No | N/A |
| Existing own PR + `--post-findings` | No | Yes — inline review | `COMMENT` |
| Existing own PR + both flags | Yes — PR comment | Yes — inline review | `COMMENT` |
| `--pr <N>` (default) | No | No | N/A |
| `--pr <N>` + `--post-findings` | No | Yes — inline review | `REQUEST_CHANGES` if Medium+; `COMMENT` if Low only |
| `--pr <N>` + `--post-summary` | Yes — PR comment | No | N/A |
| `--pr <N>` + `--post-summary --post-findings` | Yes — PR comment | Yes — inline review | `REQUEST_CHANGES` if Medium+; `COMMENT` if Low only |
| `--pr <N>` + `--no-findings` | No | No | N/A |
| Any + `--no-post` / `--local` | No | No | N/A (explicit alias for the default) |

**Inline comment cap:** The top 25 findings by severity are posted as inline comments. Additional findings appear in the review body, preventing API throttling on large finding sets.

> **Note:** Bitbucket does not support inline diff comments via API. When `--post-findings` is used with Bitbucket, findings are posted as a single PR comment instead of inline.
{: .note }
