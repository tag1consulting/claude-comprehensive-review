# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

This repo distributes a Claude Code skill (`/comprehensive-review`) and six custom agents as a Claude Code plugin. There is no build system, test suite, or compiled output — the deliverables are markdown files distributed via the `tag1consulting` plugin marketplace or copied into `~/.claude/` by a legacy install script.

## Installation (for testing changes locally)

```bash
./install.sh --local
```

This copies files from the local working tree into `~/.claude/` without fetching from GitHub. Changes take effect immediately in the next Claude Code session. This is the recommended method for contributors testing local changes. For end-user installation, use `/plugins install comprehensive-review@tag1consulting` inside Claude Code.

## Architecture

The skill and agents are entirely Claude Code markdown files. Understanding how they fit together:

### Two-tier agent model

The skill coordinates two groups of agents:

1. **Custom agents in this repo** (`agents/`) — owned here, distributed with this package:
   - `pr-summarizer` — generates the GitHub-facing PR description (Block A)
   - `issue-linker` — cross-references GitHub issues and PRs
   - `security-reviewer` — OWASP-class security analysis (runs Opus)
   - `architecture-reviewer` — design pattern and coupling analysis (runs Opus)
   - `blind-hunter` — context-free "fresh eyes" review; receives only the raw diff (small diffs), a plain file list (large diffs in normal mode), or a concatenated per-file diff assembled by the orchestrator (large diffs in `--pr` mode) — no project context in any case (runs Sonnet). Adapted from BMAD-METHOD.
   - `edge-case-hunter` — mechanical boundary-condition path tracing (runs Sonnet). Adapted from BMAD-METHOD.

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
- **blind-hunter** receives zero project context by design; it is orthogonal to all other agents. Overlap is expected and handled by deduplication. Do not try to scope-limit it — the independent perspective is the point.
- **edge-case-hunter** asks "does a handling path exist?"; **silent-failure-hunter** asks "is the existing error handling adequate?" — these are distinct questions with minimal overlap. **edge-case-hunter** does not report security implications of gaps (that's **security-reviewer**'s domain).

### Two-block output design

The skill produces two distinct output blocks with different audiences:

- **Block A** (informational) — summary, walkthrough table, Mermaid diagrams, related issues. Contains no findings.
- **Block B** (findings) — severity-ranked issues from all agents. Always displayed in the terminal.

Both blocks are always shown locally. What gets posted to GitHub depends on context:

| Scenario | Block A | Block B |
|----------|---------|---------|
| No PR exists (default) | Not posted | Not posted |
| No PR exists + `--create-pr` | PR description | Not posted |
| No PR exists + `--create-pr --post-findings` | PR description | Inline GitHub review (`COMMENT` event) |
| Existing own PR (default) | Not posted | Not posted |
| Existing own PR + `--post-summary` | PR comment | Not posted |
| Existing own PR + `--post-findings` | Not posted | Inline GitHub review (`COMMENT` event) |
| `--pr <N>` mode (default) | Not posted | Inline GitHub review (`REQUEST_CHANGES` if Medium+, `COMMENT` if Low) |
| `--pr <N>` + `--post-summary` | PR comment | Inline GitHub review |
| `--pr <N>` + `--no-findings` | Not posted | Not posted |
| Any + `--no-post`/`--local` | Not posted | Not posted |

The key invariant: Block A is posted only when `--create-pr` is passed and no PR exists. On existing PRs, both blocks require explicit opt-in flags. Block B is never hidden from the terminal.

### Severity normalization

Each agent uses its own severity scale. The skill's `SKILL.md` defines a normalization table (Phase 2) that maps agent-specific scales to a unified Critical/High/Medium/Low scale, and deduplicates findings when two agents flag the same `file:line`.

### Agent tiers

Agents are divided into three tiers:

1. **Always-run:** pr-summarizer, code-reviewer — run in every mode including `--quick`
2. **Full-run only (skip with `--quick`):** architecture-reviewer, security-reviewer, blind-hunter, edge-case-hunter, comment-analyzer, type-design-analyzer, issue-linker
3. **Conditional (run in both full and `--quick` when triggered by diff content):** silent-failure-hunter (error patterns), pr-test-analyzer (test files)

The `--quick` flag eliminates the two expensive Opus review agents, the two BMAD-inspired Sonnet agents (blind-hunter, edge-case-hunter), and the lower-value conditional agents, reducing cost by ~75% while preserving the core code review and error/test analysis.

### External PR review mode

When `--pr <N>` is passed, the skill:
1. Fetches the PR metadata via `gh pr view`
2. Creates a temporary worktree and checks out the PR branch
3. Runs the standard analysis pipeline against the worktree
4. Posts findings as an inline GitHub review (REQUEST_CHANGES if Medium+ findings, COMMENT if Low only)
5. Cleans up the worktree in Phase 5

This allows reviewing any accessible PR without being on that branch locally.

## Distribution

This project is distributed as a Claude Code plugin via the `tag1consulting` marketplace (hosted at `tag1consulting/claude-plugins` on GitHub). The `install.sh` script is maintained as a legacy fallback.

### Version management

When releasing a new version:
1. Update `version` in `.claude-plugin/plugin.json`
2. Update the plugin entry's `version` in the `tag1consulting/claude-plugins` marketplace repo
3. Tag this repo with `v<version>` (e.g., `v1.0.0`)

Plugin versions use semver without the `v` prefix (e.g., `1.0.0`). Git tags use the `v` prefix (e.g., `v1.0.0`).

## File layout

```
.claude-plugin/plugin.json             ← plugin manifest (name, version, author, keywords)
skills/comprehensive-review/SKILL.md   ← orchestrator: phases 0–5, all workflow logic
agents/pr-summarizer.md                ← Block A generation
agents/issue-linker.md                 ← GitHub issue cross-referencing
agents/security-reviewer.md            ← security analysis
agents/architecture-reviewer.md        ← architectural analysis
agents/blind-hunter.md                 ← context-free "fresh eyes" review (adapted from BMAD-METHOD)
agents/edge-case-hunter.md             ← boundary-condition path tracing (adapted from BMAD-METHOD)
install.sh                             ← legacy file-copy installer (recommends plugin install)
```

## Editing guidelines

- **`SKILL.md`** is the source of truth for workflow logic, flag handling, severity normalization, and the Phase 0–5 execution order. Changes to agent behavior or output format must be reflected here.
- **Agent files** define what each agent does and its scope boundaries. Agents reference each other only to delineate responsibility boundaries — coordination and context passing happens entirely in `SKILL.md`. Agent task descriptions reference the file-manifest protocol (receiving manifests, using `git diff <base>...HEAD -- <file>` for selective reads); changes to the context-passing strategy in `SKILL.md` require corresponding updates to agent task descriptions.
- **`README.md` and `CLAUDE.md`** must stay in sync with `SKILL.md` — specifically the flags table, agent roster, and output structure sections.
- When adding a new agent to the skill, add it to: the agent roster table in `README.md`, the Phase 1 launch conditions in `SKILL.md`, and the severity normalization table in `SKILL.md` if it uses a non-standard scale.
- The `allowed-tools` frontmatter in `SKILL.md` controls which tools the orchestrator can use. When adding GitHub write operations, add the corresponding `mcp__github-pat__*` tool there.
- When modifying `--quick` behavior, update the mode flag table in Phase 1 of `SKILL.md`, the flags section at the top of `SKILL.md`, the flags table in `README.md`, and the `--help` text block in Phase 0.
- **blind-hunter** has a unique context constraint: it must receive ONLY the diff or plain file list — no manifest, no project context, no commit log. If you change the context-passing strategy in `SKILL.md`, verify blind-hunter's constraint is still enforced. The agent file itself also instructs the agent to ignore any extra context it receives.
- **BMAD attribution**: `blind-hunter` and `edge-case-hunter` were adapted from BMAD-METHOD (MIT License, BMad Code LLC). Attribution is present in both agent files and in README.md. Do not remove attribution when editing these agents.
