# comprehensive-review

A Claude Code skill that runs a full CodeRabbit-style PR/MR review using a parallel fleet of specialized agents. Supports GitHub (including Enterprise), GitLab, and Bitbucket repositories. Produces a structured PR/MR summary and a findings report. Supports reviewing your own branch before opening a PR/MR, or reviewing an existing PR/MR by number.

## What it does

When you run `/comprehensive-review` on a branch, it:

1. Launches specialized review agents **in parallel**, using token-efficient context passing
2. Normalizes and deduplicates their findings into a unified severity ranking
3. Assembles two output blocks:
   - **Block A (informational)** — Summary, file walkthrough table, Mermaid sequence diagrams (opt-in via `--diagrams`), effort estimate, related issues/PRs
   - **Block B (findings)** — Critical/High/Medium/Low findings, architectural insights, security analysis, recommended actions
4. Posts Block A and/or Block B to the hosting provider based on the flags and scenario (see [Posting behavior](#posting-behavior))

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
| **Mermaid sequence diagrams** | No | Yes (pr-summarizer, opt-in via `--diagrams`) |
| **Related issue/PR discovery** | No | Yes (issue-linker) |
| **Unified severity ranking** | Per-agent only | Normalized across all agents, deduplicated |
| **Inline PR/MR review posting** | No | Yes (`--post-findings`, `--pr`) |
| **External PR/MR review (others' PRs/MRs)** | No | Yes (`--pr <N>`) |
| **PR description auto-creation** | No | Yes (creates PR from Block A) |
| **Token-efficient context passing** | Per-agent | Coordinated (manifest, shared context, sliced diffs) |

In short: pr-review-toolkit agents handle tactical code review. This skill orchestrates them alongside higher-level analysis agents, produces a cohesive report, and handles all remote operations — including posting findings as inline reviews on any PR/MR.

## Requirements

| Requirement | Notes |
|-------------|-------|
| [Claude Code](https://claude.ai/code) | CLI or desktop app |
| `git` | Required for diff analysis |
| [gh CLI](https://cli.github.com/) | Required for GitHub / GitHub Enterprise |
| [glab CLI](https://gitlab.com/gitlab-org/cli) | Required for GitLab |
| `BITBUCKET_EMAIL` env var | Required for Bitbucket — your Atlassian account email address |
| `BITBUCKET_TOKEN` env var | Required for Bitbucket — Atlassian API token from `id.atlassian.com` (`BITBUCKET_APP_PASSWORD` is auto-mapped if set) |
| `jq` | Required for GitLab and Bitbucket (JSON parsing) |
| `pr-review-toolkit@claude-plugins-official` | Required plugin — provides code-reviewer, silent-failure-hunter, pr-test-analyzer, comment-analyzer, type-design-analyzer |

## Provider support

| Feature | GitHub / GHE | GitLab | Bitbucket |
|---------|:---:|:---:|:---:|
| Auto-detection | Yes | Yes | Yes |
| PR/MR creation (`--create-pr`) | Yes | Yes | Yes |
| Summary posting (`--post-summary`) | Yes | Yes | Yes |
| Inline review posting (`--post-findings`) | Yes | Yes | No ¹ |
| External review (`--pr <N>`) | Yes | Yes | Yes |
| Inline review on external PR | Yes | Yes | No ¹ |
| Issue cross-referencing (issue-linker) | Yes | No ² | No ² |

¹ Bitbucket does not support inline diff comments via API. Findings are posted as a single PR comment.
² Issue cross-referencing is currently GitHub-only. The issue-linker agent is gracefully skipped for other providers.

## Installation

### Option 1: Plugin install (recommended)

First, add the Tag1 Consulting marketplace (one-time setup, run in your terminal):

```bash
claude plugin marketplace add tag1consulting/claude-plugins
```

Then inside Claude Code, install the plugin and its dependency:

```
/plugins install comprehensive-review@tag1consulting
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
cp skills/comprehensive-review/HELP.md ~/.claude/skills/comprehensive-review/
cp skills/comprehensive-review/PROVIDERS.md ~/.claude/skills/comprehensive-review/
cp skills/comprehensive-review/SEVERITY.md ~/.claude/skills/comprehensive-review/

# Agents
mkdir -p ~/.claude/agents
cp agents/pr-summarizer.md ~/.claude/agents/
cp agents/issue-linker.md ~/.claude/agents/
cp agents/security-reviewer.md ~/.claude/agents/
cp agents/architecture-reviewer.md ~/.claude/agents/
cp agents/blind-hunter.md ~/.claude/agents/
cp agents/edge-case-hunter.md ~/.claude/agents/

# Scripts
mkdir -p ~/.claude/scripts
cp scripts/run-cve-check.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/run-cve-check.sh
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
| `--quick` | Fast mode: pr-summarizer + code-reviewer + triggered error/test agents only. Skips security, architecture, blind-hunter, edge-case-hunter, comment, and type analysis. Roughly 60–80% cheaper depending on diff composition. |
| `--diagrams` | Include Mermaid sequence diagrams in Block A. Default is omitted (saves hundreds of output tokens). Always omitted in `--quick`. |
| `--security-only` | Run security-reviewer + CVE check on changed dependency manifests only |
| `--depth <tier>` | Agent depth: `normal` (default) or `deep`. In `deep` mode, blind-hunter and edge-case-hunter run on the `opus` alias, Opus agents use extended step-by-step reasoning, and a CVE reachability triage pass annotates which vulnerabilities are reachable in the diff. |
| `--summary-only` | Run only the pr-summarizer agent |
| `--create-pr` | Create a PR using Block A as the description. Without this flag, no PR is created. |
| `--post-summary` | Post Block A (summary) as a comment on an existing PR/MR |
| `--post-findings` | Post Block B (findings) as inline review on an existing own PR/MR |
| `--no-findings` | Suppress posting findings as a review (useful for dry-run with `--pr`) |
| `--no-post` / `--local` | Display everything locally, skip all remote operations |
| `--pr <number>` | Review an existing PR/MR by number (external review mode) |
| `--provider <name>` | Override auto-detected git provider (`github`, `gitlab`, `bitbucket`) |
| `--no-mem` | Disable claude-mem integration (auto-detected when available) |
| `--output-file <path>` | Write Block A + Block B to a markdown file during Phase 5. Avoids re-running the review in a fresh session just to save the output — saves ~$5–15 on large PRs where the post-review context would otherwise force a new expensive session. |
| `--help` | Show usage |

### Examples

```bash
# Full review — everything shown locally, no PR created
/comprehensive-review

# Review and create a PR with the summary as its description
/comprehensive-review --create-pr

# Fast review — roughly 60–80% cheaper, skips security and architecture agents
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

# Security scan only (includes CVE check on changed dependency manifests)
/comprehensive-review --security-only --local

# Deep review — Opus for all agents + extended reasoning + CVE reachability triage
/comprehensive-review --depth deep
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
| `--pr <N>` (default) | No | Yes — inline review | `REQUEST_CHANGES` if Medium+ findings; `COMMENT` if Low only |
| `--pr <N>` + `--post-summary` | Yes — PR comment | Yes — inline review | (same) |
| `--pr <N>` + `--no-findings` | No | No | N/A |
| Any + `--no-post` / `--local` | No | No | N/A |

**Inline comment cap:** The top 25 findings by severity are posted as inline comments. Any additional findings appear in the review body. This prevents API throttling on large finding sets.

## Agent roster

Opus agents (`architecture-reviewer`, `security-reviewer`) use the `opus` alias, which the Claude Code harness resolves to the current Opus model at spawn time. In `--depth deep` mode, `blind-hunter` and `edge-case-hunter` also resolve to the `opus` alias. The spawn indicator shown by Claude Code displays the resolved version for each subagent.

### Full run

| Agent | Model | Purpose | When it runs | Context |
|-------|-------|---------|--------------|---------|
| **pr-summarizer** | Sonnet | Summary, walkthrough table, Mermaid diagrams (opt-in), effort score | Always | Manifest + selective reads ² |
| **code-reviewer** ¹ | Sonnet | Tactical bugs, style violations, project conventions | Always | Full diff |
| **architecture-reviewer** | Opus | System design, coupling, API design, technical debt | Full run only | Manifest + selective reads ² |
| **security-reviewer** | Opus | OWASP-class security analysis, language-specific checks | Full run only | Manifest + selective reads ² |
| **silent-failure-hunter** ¹ | — | Silent failures, inadequate error handling | If diff has error-handling patterns | Relevant file slices |
| **pr-test-analyzer** ¹ | — | Test coverage gaps | If test files appear in the diff | Relevant file slices |
| **comment-analyzer** ¹ | — | Comment accuracy and rot | Full run only, if diff adds/modifies comments | Relevant file slices |
| **type-design-analyzer** ¹ | — | Type/struct/interface invariants | Full run only, if diff adds type definitions | Relevant file slices |
| **blind-hunter** | Sonnet | Context-free "fresh eyes" review: catches issues familiarity blinds other agents to | Full run only | Raw diff only (no project context) |
| **edge-case-hunter** | Sonnet | Mechanical path tracing: missing else/default, unguarded inputs, off-by-one, overflow, race conditions, resource leaks | Full run only | Manifest + selective reads ² |
| **issue-linker** | Haiku | Finds referenced issues and related PRs/issues (GitHub only) | Full run only; skipped in `--pr`, `--local`/`--no-post`, and non-GitHub repos | Commit log + branch + manifest |

### Deterministic checks

In addition to LLM agents, the skill runs a deterministic CVE check when dependency manifests are in the diff:

| Check | Trigger | Runs in `--quick`? |
|-------|---------|-------------------|
| **dependency-check** — queries [OSV.dev](https://osv.dev/) for known vulnerabilities in declared dependency versions | `go.mod`, `package.json`, `requirements*.txt`, or `composer.json` changed | Yes |

No API key required. Network failures are non-blocking (returns empty, warns to stderr). Findings appear in Block B as `[dependency-check]` entries.

### `--quick` mode

Skips: architecture-reviewer, security-reviewer, blind-hunter, edge-case-hunter, comment-analyzer, type-design-analyzer, issue-linker.
Still runs: pr-summarizer (no diagrams), code-reviewer, triggered silent-failure-hunter / pr-test-analyzer, and the CVE check if manifest files changed.

¹ From the `pr-review-toolkit@claude-plugins-official` plugin.
² For small diffs (under 300 lines), the full diff is passed inline instead.

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

PR/MR description (Block A only — no findings):
```
## Summary
## Walkthrough
## Sequence Diagrams  (only with --diagrams)
## Related Issues & PRs
```

Inline review (Block B — when `--post-findings` or `--pr` mode):
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
~/.claude/skills/comprehensive-review/HELP.md
~/.claude/skills/comprehensive-review/PROVIDERS.md
~/.claude/skills/comprehensive-review/SEVERITY.md
~/.claude/agents/pr-summarizer.md
~/.claude/agents/issue-linker.md
~/.claude/agents/security-reviewer.md
~/.claude/agents/architecture-reviewer.md
~/.claude/agents/blind-hunter.md
~/.claude/agents/edge-case-hunter.md
```

The `pr-review-toolkit` plugin installs its agents to `~/.claude/plugins/` automatically.

## Cost expectations

**Orchestrator model matters most.** The orchestrator coordinates workflow and normalizes findings — it does not need Opus-level reasoning. Run this skill on **Sonnet** for ~5× lower orchestrator cost. Opus is reserved for the internally-spawned `architecture-reviewer` and `security-reviewer` agents.

| Orchestrator model | Typical cost (medium PR, ~1,700 lines, full run) |
|--------------------|------------------------------------------------:|
| Opus 4.7 | **$60–80** |
| Sonnet 4.6 (recommended) | **$30–45** |

Cost drivers:
- ~80% of cost comes from the two Opus specialist agents (architecture-reviewer, security-reviewer) and the orchestrator itself when run on Opus.
- The orchestrator accumulates ~100k+ cached tokens over 100+ tool-call turns; at Opus cache-read rates ($1.50/M) this alone costs ~$15–30 per review.
- At Sonnet cache-read rates ($0.30/M) the same context costs ~$3–6.

**Cost-saving options:**
- `--quick`: skips architecture-reviewer, security-reviewer, and four other agents. Roughly 60–80% cheaper.
- `--depth normal` (default): Opus reserved for 2 agents. `--depth deep` promotes 2 more to Opus and roughly doubles cost.
- `--output-file <path>`: writes the report to disk during the review session, so you don't need a separate follow-up request that pays Opus rates against a large accumulated context.

## Token efficiency

The skill uses a tiered context-passing strategy to minimize token consumption:

- **Small diffs (<300 lines):** Full diff passed inline to all agents — the overhead of selective reads exceeds the cost.
- **Medium/large diffs (300+ lines):** Custom agents receive a structured file manifest and read specific files on demand. Toolkit agents receive only the diff slices relevant to their specialty.
- **Pre-flight context sharing:** The orchestrator reads CLAUDE.md and the commit log once in Phase 0 and passes condensed versions to agents, eliminating redundant reads.
- **Agent scope boundaries:** Explicit boundaries prevent duplicate analysis across agents (e.g., security-reviewer handles dependency security, architecture-reviewer handles dependency architecture).
- **`--quick` mode:** Skips the two Opus review agents (architecture-reviewer, security-reviewer), the two BMAD-inspired agents (blind-hunter, edge-case-hunter), and the two lower-value conditional agents (comment-analyzer, type-design-analyzer). Roughly 60–80% cheaper vs. full run depending on diff composition (measured: ~79K agent tokens for --quick vs ~317K for a full run on a documentation PR; code-heavy PRs with deeper Opus analysis yield higher savings).
- **blind-hunter cost:** Particularly cheap — it receives only the raw diff or plain file list, with no project context passed at all.
- **Per-file diff digest:** The orchestrator pre-computes a compact per-file summary (stat line + first changed hunk, ≤20 lines per file, capped at 200 total lines) and passes it to Opus agents upfront. This allows them to prioritize which files to investigate deeply without burning tool calls on discovery, reducing the cache-read multiplier that accumulates with every tool turn.
- **Opus agent tool-call budget:** architecture-reviewer and security-reviewer are instructed to prefer parallel batched reads and stop at 25 tool calls. Phase 5 reports actual tool-call counts with a warning if the budget is exceeded, making regressions visible.
- **Token utilization table:** Phase 5 always prints a per-agent breakdown of input/output/cache tokens and estimated USD cost, so you can see where budget is going without running `/cost`.

## claude-mem integration (optional)

If [claude-mem](https://github.com/thedotmack/claude-mem) is installed, the skill automatically integrates with it:

- **Detects** the worker daemon via health check in Phase 0
- **Retrieves** up to 5 prior review summaries for the same project and passes them to architecture-reviewer and security-reviewer as pattern context (~500 tokens)
- **Stores** a compact review summary after each run (project slug, branch, findings counts, top 3 findings, agents run)

No configuration needed. Use `--no-mem` to opt out.

> **Note:** Review summaries including finding descriptions are stored in claude-mem's local database, accessible to any process on localhost. Avoid using this integration in shared or multi-tenant environments.

### Token economics

| Operation | Token cost |
|-----------|-----------|
| Detection (health check) | ~0 (Bash, no LLM tokens) |
| MCP search index (5 results) | ~250–500 tokens |
| PRIOR_REVIEW_CONTEXT passed to 2 agents | ~500 tokens max |
| Summary storage (curl POST) | ~0 (Bash, no LLM tokens) |
| **Total overhead per run** | **~750–1,000 tokens** |

Break-even: if the prior-review context helps architecture-reviewer or security-reviewer skip ~1,000 tokens of re-analysis on a recurring pattern, the integration pays for itself. On a typical full run (50K–200K tokens), this is a rounding error. The value is qualitative: recurring issues are more likely to be flagged and labeled as patterns rather than isolated findings.

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
rm -f ~/.claude/scripts/run-cve-check.sh
```
