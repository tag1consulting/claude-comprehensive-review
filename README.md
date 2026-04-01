# comprehensive-review

A Claude Code skill that runs a full CodeRabbit-style PR review using a parallel fleet of specialized agents. Produces a structured PR summary and a findings report. Supports reviewing your own branch before opening a PR, or reviewing an existing PR by number.

## What it does

When you run `/comprehensive-review` on a branch, it:

1. Launches specialized review agents **in parallel**, using token-efficient context passing
2. Normalizes and deduplicates their findings into a unified severity ranking
3. Assembles two output blocks:
   - **Block A (informational)** — Summary, file walkthrough table, Mermaid sequence diagrams, effort estimate, related issues/PRs
   - **Block B (findings)** — Critical/High/Medium/Low findings, architectural insights, security analysis, recommended actions
4. Posts Block A and/or Block B to GitHub based on the flags and scenario (see [Posting behavior](#posting-behavior))

## Why this vs. pr-review-toolkit alone?

The `pr-review-toolkit` plugin provides excellent code-level agents (bug detection, error handling, test coverage, comment quality, type design). This skill layers on top of it to provide:

| Capability | pr-review-toolkit | comprehensive-review |
|------------|-------------------|---------------------|
| Code-level bug and style review | Yes (code-reviewer) | Yes (reuses code-reviewer) |
| Error handling analysis | Yes (silent-failure-hunter) | Yes (reused) |
| Test coverage gaps | Yes (pr-test-analyzer) | Yes (reused) |
| Comment quality | Yes (comment-analyzer) | Yes (reused) |
| Type design analysis | Yes (type-design-analyzer) | Yes (reused) |
| **OWASP-class security analysis** | No | Yes (security-reviewer, Opus) |
| **Architecture and coupling analysis** | No | Yes (architecture-reviewer, Opus) |
| **Context-free "fresh eyes" review** | No | Yes (blind-hunter, Sonnet) |
| **Mechanical boundary-condition tracing** | No | Yes (edge-case-hunter, Sonnet) |
| **PR summary + walkthrough table** | No | Yes (pr-summarizer) |
| **Mermaid sequence diagrams** | No | Yes (pr-summarizer) |
| **Related issue/PR discovery** | No | Yes (issue-linker) |
| **Unified severity ranking** | Per-agent only | Normalized across all agents, deduplicated |
| **Inline GitHub PR review posting** | No | Yes (`--post-findings`, `--pr`) |
| **External PR review (others' PRs)** | No | Yes (`--pr <N>`) |
| **PR description auto-creation** | No | Yes (creates PR from Block A) |
| **Token-efficient context passing** | Per-agent | Coordinated (manifest, shared context, sliced diffs) |

In short: pr-review-toolkit agents handle tactical code review. This skill orchestrates them alongside higher-level analysis agents, produces a cohesive report, and handles all GitHub operations — including posting findings as inline reviews on any PR.

## Requirements

| Requirement | Notes |
|-------------|-------|
| [Claude Code](https://claude.ai/code) | CLI or desktop app |
| [gh CLI](https://cli.github.com/) | Required for PR creation and GitHub reads |
| `git` | Required for diff analysis |
| `pr-review-toolkit@claude-plugins-official` | Required plugin — provides code-reviewer, silent-failure-hunter, pr-test-analyzer, comment-analyzer, type-design-analyzer |

## Installation

### Option 1: Plugin install (recommended)

Inside Claude Code:

```
/plugins install comprehensive-review@tag1consulting
```

Then install the required dependency:

```
/plugins install pr-review-toolkit@claude-plugins-official
```

### Option 2: Install script (legacy)

```bash
git clone https://github.com/tag1consulting/claude-comprehensive-review.git
cd claude-comprehensive-review
./install.sh
```

The script automatically installs the latest release, fetching files directly from GitHub. The `pr-review-toolkit` plugin is installed automatically as well.

**Install a specific version:**

```bash
./install.sh --version v1.2.0
```

**Install the development version from `main`:**

```bash
./install.sh --version main
```

**Install from local files** (for contributors testing changes):

```bash
./install.sh --local
```

### Option 3: Manual installation

Copy files to your Claude config directory (default: `~/.claude`):

```bash
# Skill
mkdir -p ~/.claude/skills/comprehensive-review
cp skills/comprehensive-review/SKILL.md ~/.claude/skills/comprehensive-review/

# Agents
mkdir -p ~/.claude/agents
cp agents/pr-summarizer.md ~/.claude/agents/
cp agents/issue-linker.md ~/.claude/agents/
cp agents/security-reviewer.md ~/.claude/agents/
cp agents/architecture-reviewer.md ~/.claude/agents/
cp agents/blind-hunter.md ~/.claude/agents/
cp agents/edge-case-hunter.md ~/.claude/agents/
```

Then install the dependency plugin inside Claude Code:

```
/plugins install pr-review-toolkit@claude-plugins-official
```

## Usage

Run from any git repository, on the branch you want to review:

```
/comprehensive-review
```

### Flags

| Flag | Effect |
|------|--------|
| `--base <branch>` | Compare against a specific base branch (default: auto-detected upstream or `main`) |
| `--quick` | Fast mode: pr-summarizer + code-reviewer + triggered error/test agents only. Skips security, architecture, blind-hunter, edge-case-hunter, comment, and type analysis. ~75% cheaper. |
| `--security-only` | Run only the security-reviewer agent |
| `--summary-only` | Run only the pr-summarizer agent |
| `--post-summary` | Post Block A (summary) as a comment on an existing PR |
| `--post-findings` | Post Block B (findings) as inline review comments on an existing own PR |
| `--no-findings` | Suppress posting findings as a review (useful for dry-run with `--pr`) |
| `--no-post` / `--local` | Display everything locally, skip all GitHub operations |
| `--pr <number>` | Review an existing PR by number (external review mode) |
| `--help` | Show usage |

### Examples

```bash
# Full review — creates PR if none exists, findings shown locally
/comprehensive-review

# Fast review — ~75% cheaper, skips security and architecture agents
/comprehensive-review --quick --local

# Review your own open PR and share findings with co-reviewers
/comprehensive-review --post-findings

# Review + post both summary and findings on your own open PR
/comprehensive-review --post-summary --post-findings

# Review someone else's PR #42 (posts findings as inline review)
/comprehensive-review --pr 42

# Review PR #42 and also post the summary as a comment
/comprehensive-review --pr 42 --post-summary

# Dry-run: review PR #42 locally, skip the findings review post
/comprehensive-review --pr 42 --no-findings

# Review against a non-default base
/comprehensive-review --base develop

# Security scan only
/comprehensive-review --security-only --local
```

## Posting behavior

| Scenario | Block A posted? | Block B posted? | Review event |
|----------|----------------|----------------|--------------|
| No PR exists (tool creates it) | Yes — PR description | No | N/A |
| Existing own PR (default) | No | No | N/A |
| Existing own PR + `--post-summary` | Yes — PR comment | No | N/A |
| Existing own PR + `--post-findings` | No | Yes — inline review | `COMMENT` |
| Existing own PR + both flags | Yes — PR comment | Yes — inline review | `COMMENT` |
| `--pr <N>` (default) | No | Yes — inline review | `REQUEST_CHANGES` if Medium+ findings; `COMMENT` if Low only |
| `--pr <N>` + `--post-summary` | Yes — PR comment | Yes — inline review | (same) |
| `--pr <N>` + `--no-findings` | No | No | N/A |
| Any + `--no-post` / `--local` | No | No | N/A |

**Inline comment cap:** The top 25 findings by severity are posted as inline comments. Any additional findings appear in the review body. This prevents API throttling on large finding sets.

## Agent roster

### Full run

| Agent | Model | Purpose | When it runs | Context |
|-------|-------|---------|--------------|---------|
| **pr-summarizer** | Sonnet | Summary, walkthrough table, Mermaid diagrams, effort score | Always | Manifest + selective reads ² |
| **code-reviewer** ¹ | Opus | Tactical bugs, style violations, project conventions | Always | Full diff |
| **architecture-reviewer** | Opus | System design, coupling, API design, technical debt | Full run only | Manifest + selective reads ² |
| **security-reviewer** | Opus | OWASP-class security analysis, language-specific checks | Full run only | Manifest + selective reads ² |
| **silent-failure-hunter** ¹ | — | Silent failures, inadequate error handling | If diff has error-handling patterns | Relevant file slices |
| **pr-test-analyzer** ¹ | — | Test coverage gaps | If test files appear in the diff | Relevant file slices |
| **comment-analyzer** ¹ | — | Comment accuracy and rot | Full run only, if diff adds/modifies comments | Relevant file slices |
| **type-design-analyzer** ¹ | — | Type/struct/interface invariants | Full run only, if diff adds type definitions | Relevant file slices |
| **blind-hunter** | Sonnet | Context-free "fresh eyes" review: catches issues familiarity blinds other agents to | Full run only | Raw diff only (no project context) |
| **edge-case-hunter** | Sonnet | Mechanical path tracing: missing else/default, unguarded inputs, off-by-one, overflow, race conditions, resource leaks | Full run only | Manifest + selective reads ² |
| **issue-linker** | Sonnet | Finds referenced issues and related PRs/issues on GitHub | Full run only | Commit log + branch + manifest |

### `--quick` mode

Skips: architecture-reviewer, security-reviewer, blind-hunter, edge-case-hunter, comment-analyzer, type-design-analyzer, issue-linker.
Still runs: pr-summarizer (no diagrams), code-reviewer, and triggered silent-failure-hunter / pr-test-analyzer.

¹ From the `pr-review-toolkit@claude-plugins-official` plugin.
² For small diffs (under 500 lines), the full diff is passed inline instead.

## Output structure

```
Terminal output:
  PR created: https://github.com/owner/repo/pull/42

  --- Review Findings ---

  Overall Risk: High

  Critical (1)
  - [security-reviewer] Hardcoded API key — config/prod.yaml:12

  High (2)
  - [code-reviewer] Nil dereference on error path — pkg/client/client.go:87
  - [architecture-reviewer] Coupling — business logic imports infra layer

  ...

  Architectural Insights
  Security Analysis
  Positive Observations
  Recommended Actions
```

GitHub PR description (Block A only — no findings):
```
## Summary
## Walkthrough
## Sequence Diagrams
## Related Issues & PRs
```

GitHub inline review (Block B — when `--post-findings` or `--pr` mode):
```
Inline comments on specific diff lines, plus a review body summary.
Uses REQUEST_CHANGES (Medium+ findings) or COMMENT (Low only).
```

## Files installed

**Plugin install** (Option 1) — files are managed by Claude Code's plugin system.
The skill and agents are auto-discovered from the plugin cache (exact path is an
implementation detail of Claude Code and may change between versions).

**Legacy install** (Option 2/3) — files copied directly:

```
~/.claude/skills/comprehensive-review/SKILL.md
~/.claude/agents/pr-summarizer.md
~/.claude/agents/issue-linker.md
~/.claude/agents/security-reviewer.md
~/.claude/agents/architecture-reviewer.md
~/.claude/agents/blind-hunter.md
~/.claude/agents/edge-case-hunter.md
```

The `pr-review-toolkit` plugin installs its agents to `~/.claude/plugins/` automatically.

## Token efficiency

The skill uses a tiered context-passing strategy to minimize token consumption:

- **Small diffs (<500 lines):** Full diff passed inline to all agents — the overhead of selective reads exceeds the cost.
- **Medium/large diffs (500+ lines):** Custom agents receive a structured file manifest and read specific files on demand. Toolkit agents receive only the diff slices relevant to their specialty.
- **Pre-flight context sharing:** The orchestrator reads CLAUDE.md and the commit log once in Phase 0 and passes condensed versions to agents, eliminating redundant reads.
- **Agent scope boundaries:** Explicit boundaries prevent duplicate analysis across agents (e.g., security-reviewer handles dependency security, architecture-reviewer handles dependency architecture).
- **`--quick` mode:** Skips the two Opus review agents (architecture-reviewer, security-reviewer), the two BMAD-inspired agents (blind-hunter, edge-case-hunter), and the two lower-value conditional agents (comment-analyzer, type-design-analyzer). Reduces cost by ~75% vs. full run (measured: ~79K agent tokens for --quick vs ~317K for a full run on a documentation PR; code-heavy PRs with deeper Opus analysis yield higher savings).
- **blind-hunter cost:** Particularly cheap — it receives only the raw diff or plain file list, with no project context passed at all.

## Acknowledgments

The `blind-hunter` and `edge-case-hunter` agents are adapted from concepts in the
[BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) project by Brian "BMad" Madison
(BMad Code LLC), released under the [MIT License](https://github.com/bmad-code-org/BMAD-METHOD/blob/main/LICENSE).

BMAD's code review workflow uses parallel adversarial review layers — a context-free "Blind Hunter"
and a path-tracing "Edge Case Hunter" — which we adapted into our agent architecture. Our
implementations differ from BMAD's originals: we use structured severity output, omit the
minimum-findings mandate, and integrate tightly with our manifest and context-passing strategy.

## Updating

**Plugin install:**

```
/plugins update comprehensive-review@tag1consulting
```

**Legacy install:**

Pull the latest version and re-run `./install.sh`. Existing agent files will be overwritten.

## Uninstalling

**Plugin install:**

```
/plugins uninstall comprehensive-review@tag1consulting
```

**Legacy install:**

```bash
rm -rf ~/.claude/skills/comprehensive-review
rm ~/.claude/agents/pr-summarizer.md
rm ~/.claude/agents/issue-linker.md
rm ~/.claude/agents/security-reviewer.md
rm ~/.claude/agents/architecture-reviewer.md
rm ~/.claude/agents/blind-hunter.md
rm ~/.claude/agents/edge-case-hunter.md
```
