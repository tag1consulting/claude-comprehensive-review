# comprehensive-review

A Claude Code skill that runs a full CodeRabbit-style pre-PR review using a parallel fleet of specialized agents. Produces a structured PR summary posted to GitHub and a private findings report for the author.

## What it does

When you run `/comprehensive-review` on a branch, it:

1. Launches up to 8 specialized review agents **in parallel** against your diff
2. Normalizes and deduplicates their findings into a unified severity ranking
3. Assembles two output blocks:
   - **Block A (informational)** — Summary, file walkthrough table, Mermaid sequence diagrams, effort estimate, related issues/PRs — posted as the PR description or a comment
   - **Block B (findings)** — Critical/High/Medium/Low findings, architectural insights, security analysis, recommended actions — displayed locally only, never posted to GitHub
4. Creates the PR (or comments on an existing one) with Block A

## Requirements

| Requirement | Notes |
|-------------|-------|
| [Claude Code](https://claude.ai/code) | CLI or desktop app |
| [gh CLI](https://cli.github.com/) | Required for PR creation and GitHub reads |
| `git` | Required for diff analysis |
| `pr-review-toolkit@claude-plugins-official` | Required plugin — provides code-reviewer, silent-failure-hunter, pr-test-analyzer, comment-analyzer, type-design-analyzer |

## Installation

### Option 1: Install script (recommended)

```bash
git clone https://github.com/your-org/claude-comprehensive-review.git
cd claude-comprehensive-review
./install.sh
```

Then install the required plugin inside Claude Code:

```
/plugins install pr-review-toolkit@claude-plugins-official
```

### Option 2: Manual installation

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
```

Then install the plugin inside Claude Code:

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
| `--quick` | Skip issue-linker and sequence diagrams — roughly half the agent cost |
| `--security-only` | Run only the security-reviewer agent |
| `--summary-only` | Run only the pr-summarizer agent |
| `--no-post` / `--local` | Display everything locally, skip all GitHub operations |
| `--help` | Show usage |

### Examples

```bash
# Full review — creates or updates PR with informational summary
/comprehensive-review

# Quick check before pushing
/comprehensive-review --quick --local

# Review against a non-default base
/comprehensive-review --base develop

# Security scan only
/comprehensive-review --security-only --local
```

## Agent roster

| Agent | Model | Purpose | When it runs |
|-------|-------|---------|--------------|
| **pr-summarizer** | Sonnet | Summary, walkthrough table, Mermaid diagrams, effort score | Always |
| **issue-linker** | Sonnet | Finds referenced issues and related PRs/issues on GitHub | Always (skip with `--quick`) |
| **security-reviewer** | Opus | OWASP-class security analysis, language-specific checks | Always |
| **architecture-reviewer** | Opus | System design, coupling, API design, technical debt | Always |
| **code-reviewer** ¹ | — | Tactical bugs, style violations, project conventions | Always |
| **silent-failure-hunter** ¹ | — | Silent failures, inadequate error handling | If diff has error-handling patterns |
| **pr-test-analyzer** ¹ | — | Test coverage gaps | If test files appear in the diff |
| **comment-analyzer** ¹ | — | Comment accuracy and rot | If diff adds or modifies comments |
| **type-design-analyzer** ¹ | — | Type/struct/interface invariants | If diff adds type definitions |

¹ From the `pr-review-toolkit@claude-plugins-official` plugin.

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

## Files installed

```
~/.claude/skills/comprehensive-review/SKILL.md   ← the /comprehensive-review command
~/.claude/agents/pr-summarizer.md
~/.claude/agents/issue-linker.md
~/.claude/agents/security-reviewer.md
~/.claude/agents/architecture-reviewer.md
```

The `pr-review-toolkit` plugin installs its agents to `~/.claude/plugins/` automatically.

## Updating

Pull the latest version and re-run `./install.sh`. Existing agent files will be overwritten.

## Uninstalling

```bash
rm -rf ~/.claude/skills/comprehensive-review
rm ~/.claude/agents/pr-summarizer.md
rm ~/.claude/agents/issue-linker.md
rm ~/.claude/agents/security-reviewer.md
rm ~/.claude/agents/architecture-reviewer.md
```
