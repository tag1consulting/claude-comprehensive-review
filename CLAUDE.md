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

- **Block A** (informational) — summary, walkthrough table, Mermaid diagrams, related issues — posted to GitHub as the PR description or comment. Contains no findings.
- **Block B** (findings) — severity-ranked issues from all agents — displayed locally only, never posted to GitHub. The author fixes these before requesting review.

This separation is intentional and load-bearing. Do not merge the blocks or post Block B to GitHub.

### Severity normalization

Each agent uses its own severity scale. The skill's `SKILL.md` defines a normalization table (Phase 2) that maps agent-specific scales to a unified Critical/High/Medium/Low scale, and deduplicates findings when two agents flag the same `file:line`.

### Conditional agent launch

The skill only spawns some agents when the diff contains relevant patterns — e.g., `silent-failure-hunter` only runs if the diff contains `catch`, `try {`, `if err`, etc. These conditions are defined in Phase 1 of `skills/comprehensive-review/SKILL.md`.

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
