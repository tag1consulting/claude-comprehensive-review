---
layout: default
title: Architecture
nav_order: 11
render_with_liquid: false
---

# Architecture

## File layout

```
.claude-plugin/plugin.json                                   ← plugin manifest (name, version, author, keywords)
skills/comprehensive-review/SKILL.md                         ← orchestrator: phases 0–5, all workflow logic
skills/comprehensive-review/HELP.md                          ← usage reference
skills/comprehensive-review/SEVERITY.md                      ← severity normalization + confidence scale
skills/comprehensive-review/GOVERNANCE.md                    ← shared governance directives (inlined into every custom agent)
skills/comprehensive-review/suppressions.json                ← global suppression rules
skills/comprehensive-review/language-profiles/               ← per-language context profiles (19 languages)
skills/comprehensive-review/scripts/run-cve-check.sh         ← deterministic CVE check via OSV.dev (Phase 1b)
skills/comprehensive-review/scripts/run-shellcheck.sh        ← ShellCheck (Phase 1b)
skills/comprehensive-review/scripts/run-semgrep.sh           ← Semgrep SAST (Phase 1b)
skills/comprehensive-review/scripts/run-trufflehog.sh        ← TruffleHog secret scanning (Phase 1b)
skills/comprehensive-review/scripts/run-ruff.sh              ← Ruff Python linting (Phase 1b)
skills/comprehensive-review/scripts/run-golangci-lint.sh     ← golangci-lint Go analysis (Phase 1b)
skills/comprehensive-review/scripts/run-checkov.sh           ← checkov IaC security scanning (Phase 1b)
skills/comprehensive-review/scripts/run-eslint.sh            ← ESLint (Phase 1b)
skills/comprehensive-review/scripts/run-hadolint.sh          ← Hadolint (Phase 1b)
skills/comprehensive-review/scripts/run-kube-linter.sh       ← kube-linter (Phase 1b)
skills/comprehensive-review/scripts/run-phpcs.sh             ← PHP CodeSniffer (Phase 1b)
skills/comprehensive-review/scripts/run-phpstan.sh           ← PHPStan (Phase 1b)
skills/comprehensive-review/scripts/run-tflint.sh            ← tflint (Phase 1b)
agents/pr-summarizer.md                                      ← Block A generation
agents/issue-linker.md                                       ← issue cross-referencing (GitHub only)
agents/security-reviewer.md                                  ← security analysis
agents/architecture-reviewer.md                              ← architectural analysis
agents/blind-hunter.md                                       ← context-free "fresh eyes" review
agents/edge-case-hunter.md                                   ← boundary-condition path tracing
agents/adversarial-general.md                                ← holistic completeness/operational review
tests/                                                       ← bats test suite (150 tests)
```

## Phase overview

The skill executes in five phases:

**Phase 0 — Setup and context gathering**
- Provider detection from git remote URL
- claude-mem health check (optional)
- Diff computation and TIER classification (tiny/small/medium)
- Language detection from changed file extensions
- Commit log and CLAUDE.md loading
- Symbol context enrichment (Phase 0c) — Grep-based cross-file definition lookup
- `GOVERNANCE_BLOCK` loading (inlined into every agent)
- Org security policy loading (Phase 0 step 10)
- Auto-cheap mode detection (DOCS_ONLY, LOW_RISK_CONFIG)

**Phase 1 — Agent and analyzer launch**
- Per-agent conditional gates (GATE_ERROR_PATTERNS, GATE_CONTROL_FLOW, GATE_SECURITY_PATTERNS, GATE_CODE_OR_INFRA) evaluated against diff
- Custom agents and toolkit agents launched in parallel
- Static analyzer scripts run in parallel (Phase 1b)

**Phase 2 — Normalization and deduplication**
- Findings collected from all agents and analyzers
- Confidence threshold filtering (`--min-confidence`)
- Suppression rules applied
- Deduplication by `file:line`
- Severity normalization to unified Critical/High/Medium/Low scale
- Secret redaction pass (defense-in-depth)

**Phase 3 — Block assembly**
- Block A (summary, walkthrough table, related issues) assembled from pr-summarizer output
- Block B (findings) assembled from normalized findings

**Phase 4 — Remote operations** (when posting flags are present)
- PR/MR creation, summary posting
- Provider-specific API calls

**Phase 4b — Findings posting** (when `--post-findings` is present)
- Stages findings as an editable draft (GitHub pending review, GitLab draft notes) by default — the human edits and submits it themselves
- `--publish` opts into immediate publishing (GitHub `REQUEST_CHANGES`/`COMMENT` review, GitLab discussion threads) instead of drafting
- `--read-back` reads an existing draft back and reports kept/edited/removed findings (GitHub and GitLab only)

**Phase 5 — Output and cleanup**
- Terminal output of Block A + Block B
- Per-agent token utilization table
- Auto-cheap mode reason reported if active
- Opus agent tool-call count warnings if budget exceeded
- claude-mem summary stored (if enabled)
- Temporary worktree cleanup (for `--pr <N>` mode)

## Two-block output design

| Block | Content | Audience |
|-------|---------|----------|
| **Block A** | Summary, walkthrough table, effort estimate, related issues/PRs | PR authors, reviewers — informational |
| **Block B** | Severity-ranked findings from all agents and analyzers | PR authors, reviewers — actionable |

Both blocks are always shown locally in the terminal. What gets posted remotely depends on the flags used — see [Usage & Flags](usage#posting-behavior) for the full posting matrix.

## Severity normalization

Each agent uses its own severity scale. The skill normalizes all findings to a unified Critical/High/Medium/Low scale via the normalization table in `SEVERITY.md`, and deduplicates findings when two agents flag the same `file:line`.

CVE findings whose CVSS vector cannot be parsed (CVSS v4.0/v2 vectors, or no severity entry) are emitted as `"High"` as a conservative fallback.

## Per-agent conditional gates

Before launching agents, Phase 1 evaluates grep-based bash gates against the diff:

| Gate | Skips agent when... |
|------|---------------------|
| `GATE_ERROR_PATTERNS` | No error-handling patterns in added lines — skip `silent-failure-hunter` |
| `GATE_CONTROL_FLOW` | No control-flow constructs in added lines — skip `edge-case-hunter` |
| `GATE_SECURITY_PATTERNS` | No security-relevant patterns or paths — skip `security-reviewer` (TIER=tiny only) |
| `GATE_CODE_OR_INFRA` | No code or infra files — skip `architecture-reviewer` (TIER=tiny only) |

## Contributing

The deterministic bash helpers in `skills/comprehensive-review/scripts/` and `tests/` have a [bats](https://github.com/bats-core/bats-core) test suite:

```bash
# Install bats (macOS)
brew install bats-core

# Run all tests
bats tests/*.bats
```

150 tests cover: `parse_go_mod` replace-directive ordering, TruffleHog invocation modes, gate evaluation logic, golden orchestration contracts (SKILL.md structural integrity, PROVIDERS.md correctness, SEVERITY.md contract), and all static analyzer scripts. All tests are offline (no network, no Claude invocation).

## Acknowledgments

The `blind-hunter` and `edge-case-hunter` agents are adapted from concepts in the [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) project by Brian "BMad" Madison (BMad Code LLC), released under the [MIT License](https://github.com/bmad-code-org/BMAD-METHOD/blob/main/LICENSE). Our implementations differ: we use structured severity output, omit the minimum-findings mandate, and integrate tightly with our manifest and context-passing strategy.
