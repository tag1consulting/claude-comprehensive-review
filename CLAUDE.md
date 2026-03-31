# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

This repo distributes a Claude Code skill (`/comprehensive-review`) and four custom agents. There is no build system, test suite, or compiled output — the deliverables are markdown files copied into a user's `~/.claude/` directory.

## Installation (for testing changes locally)

```bash
./install.sh --local
```

This copies files from the local working tree into `~/.claude/` without fetching from GitHub. Changes take effect immediately in the next Claude Code session. Omitting `--local` will fetch the latest release from GitHub instead.

## Architecture

The skill and agents are entirely Claude Code markdown files. Understanding how they fit together:

### Two-tier agent model

The skill coordinates two groups of agents:

1. **Custom agents in this repo** (`agents/`) — owned here, distributed with this package:
   - `pr-summarizer` — generates the GitHub-facing PR description (Block A)
   - `issue-linker` — cross-references GitHub issues and PRs
   - `security-reviewer` — OWASP-class security analysis (runs Opus)
   - `architecture-reviewer` — design pattern and coupling analysis (runs Opus)

2. **pr-review-toolkit agents** — external dependency, installed separately via `/plugins install pr-review-toolkit@claude-plugins-official`:
   - `code-reviewer`, `silent-failure-hunter`, `pr-test-analyzer`, `comment-analyzer`, `type-design-analyzer`
   - These are not in this repo and must not be duplicated here

### Token-efficient context passing

The orchestrator uses a tiered approach to minimize token consumption:

- **Small diffs (under 500 lines)**: Full diff passed inline to all agents — at this size, the tool-call overhead of selective reads exceeds the token cost of including the full diff.
- **Medium/large diffs (500+ lines)**: Custom agents receive a structured **file manifest** (file list, categories, languages, line counts) and use selective `git diff <base>...HEAD -- <file>` reads. Toolkit agents (which we cannot modify) receive only the diff slices relevant to their specialty.

The orchestrator also pre-reads CLAUDE.md and the commit log in Phase 0, passing condensed versions to agents so they don't fetch these independently.

### Agent scope boundaries

To reduce duplicate analysis and wasted tokens, each agent has explicit scope boundaries:
- **security-reviewer** owns security implications of dependencies; **architecture-reviewer** owns architectural implications
- **security-reviewer** does not report error handling quality issues — that's **silent-failure-hunter**'s domain
- **architecture-reviewer** focuses on structural maintainability, not code-level style — that's **code-reviewer**'s domain

### Two-block output design

The skill produces two distinct output blocks with different audiences:

- **Block A** (informational) — summary, walkthrough table, Mermaid diagrams, related issues. Contains no findings.
- **Block B** (findings) — severity-ranked issues from all agents. Always displayed in the terminal.

Both blocks are always shown locally. What gets posted to GitHub depends on context:

| Scenario | Block A | Block B |
|----------|---------|---------|
| No PR exists (tool creates it) | PR description | Not posted |
| Existing own PR (default) | Not posted | Not posted |
| Existing own PR + `--post-summary` | PR comment | Not posted |
| Existing own PR + `--post-findings` | Not posted | Inline GitHub review (`COMMENT` event) |
| `--pr <N>` mode (default) | Not posted | Inline GitHub review (`REQUEST_CHANGES` if Medium+, `COMMENT` if Low) |
| `--pr <N>` + `--post-summary` | PR comment | Inline GitHub review |
| Any + `--no-post`/`--local` | Not posted | Not posted |

The key invariant: Block A is auto-posted only when *creating* a new PR. On existing PRs, both blocks require explicit opt-in flags. Block B is never hidden from the terminal.

### Severity normalization

Each agent uses its own severity scale. The skill's `SKILL.md` defines a normalization table (Phase 2) that maps agent-specific scales to a unified Critical/High/Medium/Low scale, and deduplicates findings when two agents flag the same `file:line`.

### Agent tiers

Agents are divided into three tiers:

1. **Always-run:** pr-summarizer, code-reviewer — run in every mode including `--quick`
2. **Full-run only (skip with `--quick`):** architecture-reviewer, security-reviewer, comment-analyzer, type-design-analyzer, issue-linker
3. **Conditional (run in both full and `--quick` when triggered by diff content):** silent-failure-hunter (error patterns), pr-test-analyzer (test files)

The `--quick` flag eliminates the two expensive Opus review agents and the lower-value conditional agents, reducing cost by ~65% while preserving the core code review and error/test analysis.

### External PR review mode

When `--pr <N>` is passed, the skill:
1. Fetches the PR metadata via `gh pr view`
2. Creates a temporary worktree and checks out the PR branch
3. Runs the standard analysis pipeline against the worktree
4. Posts findings as an inline GitHub review (REQUEST_CHANGES if Medium+ findings, COMMENT if Low only)
5. Cleans up the worktree in Phase 5

This allows reviewing any accessible PR without being on that branch locally.

## File layout

```
skills/comprehensive-review/SKILL.md   ← orchestrator: phases 0–5, all workflow logic
agents/pr-summarizer.md                ← Block A generation
agents/issue-linker.md                 ← GitHub issue cross-referencing
agents/security-reviewer.md            ← security analysis
agents/architecture-reviewer.md        ← architectural analysis
install.sh                             ← copies files into ~/.claude/
```

## Editing guidelines

- **`SKILL.md`** is the source of truth for workflow logic, flag handling, severity normalization, and the Phase 0–5 execution order. Changes to agent behavior or output format must be reflected here.
- **Agent files** define what each agent does and its scope boundaries. Agents reference each other only to delineate responsibility boundaries — coordination and context passing happens entirely in `SKILL.md`. Agent task descriptions reference the file-manifest protocol (receiving manifests, using `git diff <base>...HEAD -- <file>` for selective reads); changes to the context-passing strategy in `SKILL.md` require corresponding updates to agent task descriptions.
- **`README.md`** must stay in sync with `SKILL.md` — specifically the flags table, agent roster, and output structure sections.
- When adding a new agent to the skill, add it to: the agent roster table in `README.md`, the Phase 1 launch conditions in `SKILL.md`, and the severity normalization table in `SKILL.md` if it uses a non-standard scale.
- The `allowed-tools` frontmatter in `SKILL.md` controls which tools the orchestrator can use. When adding GitHub write operations, add the corresponding `mcp__github-pat__*` tool there.
- When modifying `--quick` behavior, update the mode flag table in Phase 1 of `SKILL.md`, the flags section at the top of `SKILL.md`, the flags table in `README.md`, and the `--help` text block in Phase 0.
