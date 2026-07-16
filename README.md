# comprehensive-review

A Claude Code skill that runs a comprehensive PR/MR review using a parallel fleet of specialized agents. Supports GitHub (including Enterprise), GitLab, and Bitbucket repositories. Produces a structured PR/MR summary and a findings report. Supports reviewing your own branch before opening a PR/MR, or reviewing an existing PR/MR by number.

## What it does

When you run `/comprehensive-review` on a branch, it:

1. Launches specialized review agents **in parallel**, using token-efficient context passing
2. Normalizes and deduplicates their findings into a unified severity ranking
3. Assembles two output blocks:
   - **Block A (informational)** — Summary, file walkthrough table, effort estimate, related issues/PRs
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
| `security-guidance@claude-plugins-official` | Recommended plugin — provides ambient hook-based security review on edits and commits. When installed, comprehensive-review's `security-reviewer` also reads its `claude-security-guidance.md` org-policy file to apply the same codebase-specific security rules. |

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

Optionally, install the security-guidance companion plugin for ambient hook-based security review:

```
/plugins install security-guidance@claude-plugins-official
```

### Option 2: Manual installation

> **Note:** As of v1.6.1, agents must be installed under the `comprehensive-review:` plugin namespace. For manual installs, lay down the full plugin tree shown below, then update `~/.claude/plugins/installed_plugins.json` to register it.

```bash
PLUGIN_DIR=~/.claude/plugins/cache/tag1consulting/comprehensive-review/<version>

# Plugin manifest
mkdir -p "$PLUGIN_DIR/.claude-plugin"
cp .claude-plugin/plugin.json "$PLUGIN_DIR/.claude-plugin/"

# Skill
mkdir -p "$PLUGIN_DIR/skills/comprehensive-review"
cp skills/comprehensive-review/SKILL.md "$PLUGIN_DIR/skills/comprehensive-review/"
cp skills/comprehensive-review/HELP.md "$PLUGIN_DIR/skills/comprehensive-review/"
cp skills/comprehensive-review/PROVIDERS.md "$PLUGIN_DIR/skills/comprehensive-review/"
cp skills/comprehensive-review/SEVERITY.md "$PLUGIN_DIR/skills/comprehensive-review/"
cp skills/comprehensive-review/suppressions.json "$PLUGIN_DIR/skills/comprehensive-review/"
cp -r skills/comprehensive-review/language-profiles "$PLUGIN_DIR/skills/comprehensive-review/"

# Agents
mkdir -p "$PLUGIN_DIR/agents"
cp agents/pr-summarizer.md "$PLUGIN_DIR/agents/"
cp agents/issue-linker.md "$PLUGIN_DIR/agents/"
cp agents/security-reviewer.md "$PLUGIN_DIR/agents/"
cp agents/architecture-reviewer.md "$PLUGIN_DIR/agents/"
cp agents/blind-hunter.md "$PLUGIN_DIR/agents/"
cp agents/edge-case-hunter.md "$PLUGIN_DIR/agents/"
cp agents/adversarial-general.md "$PLUGIN_DIR/agents/"

# Scripts
mkdir -p "$PLUGIN_DIR/skills/comprehensive-review/scripts"
for s in skills/comprehensive-review/scripts/*.sh; do
  cp "$s" "$PLUGIN_DIR/skills/comprehensive-review/scripts/"
  chmod +x "$PLUGIN_DIR/skills/comprehensive-review/scripts/$(basename "$s")"
done
```

Then register the plugin in `~/.claude/plugins/installed_plugins.json` (add or update the `comprehensive-review@tag1consulting` key) and install the dependency plugin inside Claude Code:

```
/plugins install pr-review-toolkit@claude-plugins-official
```

Optionally, install the security-guidance companion plugin:

```
/plugins install security-guidance@claude-plugins-official
```

## Org security policy

Both `comprehensive-review` and the `security-guidance` plugin read the same
`claude-security-guidance.md` policy file — drop one in any of these locations to have
both tools apply the same codebase-specific security rules automatically:

| Path | Scope |
|------|-------|
| `~/.claude/claude-security-guidance.md` | User-wide (all repos) |
| `<repo>/.claude/claude-security-guidance.md` | Project-wide (commit this) |
| `<repo>/.claude/claude-security-guidance.local.md` | Local overrides (gitignore this) |

All three are loaded and concatenated in the order above (user → project → project-local)
into the security-reviewer's task description. The combined budget is capped at 8 KB
(matching the security-guidance plugin) — if the files exceed this, the tail
(project-local) is truncated first, preserving user-wide rules.

Example `claude-security-guidance.md`:

```markdown
# Org security rules

- All SELECTs against the `customers` or `orders` tables MUST go through `db.replica`.
- Background jobs must not use the user-context auth token; use service-account creds.
- Calls to `requests.get(url)` with user-controlled input need the SSRF-allowlist wrapper.
```

For a fuller annotated starting point, copy
[`examples/claude-security-guidance.example.md`](examples/claude-security-guidance.example.md)
into your repo's `.claude/` directory and rename it to `claude-security-guidance.md`.

When a finding is triggered by a policy rule, the security-reviewer cites the specific
rule in the finding text. If no policy file exists, the security-reviewer falls back to
its universal checks — the review runs fully without it.

## Usage

Run from any git repository, on the branch you want to review:

```
/comprehensive-review
```

### Flags

| Flag | Effect |
|------|--------|
| `--base <branch>` | Compare against a specific base branch (default: auto-detected upstream or `main`) |
| `--quick` | Fast mode: pr-summarizer + code-reviewer + triggered error/test agents only. Skips security, architecture, blind-hunter, edge-case-hunter, comment, and type analysis. Roughly 60–80% cheaper depending on diff composition. When the diff is also tiny (<50 lines, ≤3 files), auto-selected TIER=tiny further demotes pr-summarizer to Haiku. No flag needed. |
| *(auto)* TIER=tiny | Automatically applied when the diff is under 50 lines AND ≤3 files. Routes pr-summarizer to Haiku; skips blind-hunter, edge-case-hunter, comment-analyzer, type-design-analyzer unconditionally; skips architecture-reviewer and security-reviewer unless triggered by infra/CI paths or auth/credential/dep-manifest paths respectively. Roughly 60–70% cheaper than `--quick` on tiny diffs (~$1 → ~$0.30). |
| *(auto)* DOCS_ONLY | Automatically applied when all changed files are documentation/markdown/meta (no code or infra). Runs pr-summarizer + code-reviewer + triggered conditionals. Skips all Opus agents and blind/edge-case/comment/type agents. Phase 5 reports the reason. Overridden by `--depth deep`, `--quick`, `--security-only`, `--summary-only`. |
| *(auto)* LOW_RISK_CONFIG | Automatically applied when the diff contains only config/YAML/TOML with no security-sensitive patterns and no dep manifests/CI files. Runs pr-summarizer + code-reviewer + deterministic checks. Skips specialist Opus agents and blind/edge-case agents. Phase 5 reports the reason. |
| `--security-only` | Run security-reviewer + CVE check on changed dependency manifests only |
| `--depth <tier>` | Agent depth: `normal` (default) or `deep`. In `deep` mode, blind-hunter and edge-case-hunter run on the `opus` alias, Opus agents use extended step-by-step reasoning, and a CVE reachability triage pass annotates which vulnerabilities are reachable in the diff. |
| `--summary-only` | Run only the pr-summarizer agent |
| `--create-pr` | Create a PR using Block A as the description. Without this flag, no PR is created. |
| `--post-summary` | Post Block A (summary) as a comment on an existing PR/MR. Unaffected by `--draft`/`--publish` on its own; when combined with `--post-findings` in draft mode, Block A rides along inside that same draft instead of a separate comment. |
| `--post-findings` | Stage Block B (findings) as inline review on an existing own PR/MR. **Stages an editable draft by default** (GitHub pending review / GitLab draft notes) — nothing is published until you submit it yourself in the web UI. Add `--publish` to post immediately instead. |
| `--no-findings` | Suppress posting findings as a review (useful for dry-run with `--pr`) |
| `--draft` | Explicit no-op alias for the default drafting behavior of `--post-findings`/`--post-summary` — pins the behavior in scripts against a future default change |
| `--publish` | Post immediately instead of staging a draft (today's pre-1.13.0 behavior). Required on Bitbucket, which has no verified draft-create path. |
| `--read-back` | Read back your edited draft (GitHub/GitLab only), report what you kept/edited/removed, and stage any newly-noticed findings — on GitLab as additional draft notes; on GitHub, reported in the terminal only (GitHub's API can't append to an existing pending review — add them yourself in the web UI). Requires an existing draft from a prior `--post-findings` run. Never publishes, never overwrites your edits. Costs the same as a full review — it re-runs analysis to regenerate the findings it compares against. |
| `--no-post` / `--local` | Explicit alias for the default: display everything locally, skip all remote operations (this is the default — posting requires explicit flags) |
| `--pr <number>` | Review an existing PR/MR by number (external review mode) |
| `--provider <name>` | Override auto-detected git provider (`github`, `gitlab`, `bitbucket`) |
| `--no-enrich-context` | Disable symbol context enrichment (Grep-based cross-file definition lookup). Context enrichment is on by default for all full runs except TIER=tiny (<50 lines, ≤3 files) — it adds ~1–3K tokens per eligible agent but reduces false positives. |
| `--no-mem` | Disable claude-mem integration (auto-detected when available) |
| `--no-suppress` | Disable all suppression rules (useful for debugging / audit runs where you want to see every finding) |
| `--min-confidence <N>` | Filter findings below this confidence threshold (0–100; default: 75; 0 disables filtering). Applied before suppression rules. |
| `--output-file <path>` | Write Block A + Block B to a markdown file during Phase 5. Avoids re-running the review in a fresh session just to save the output. |

### Examples

```bash
# Full review — everything shown locally, no PR created
/comprehensive-review

# Review and create a PR with the summary as its description
/comprehensive-review --create-pr

# Fast review — roughly 60–80% cheaper, skips security and architecture agents
/comprehensive-review --quick

# Review your own open PR and stage findings as your editable draft review
# (GitHub: pending review; GitLab: draft notes — nothing published until you submit it)
/comprehensive-review --post-findings

# Same, but publish immediately instead of staging a draft (pre-1.13.0 behavior)
/comprehensive-review --post-findings --publish

# After editing your staged draft in the web UI, ask the AI to read it back
# and flag anything you missed or got wrong (GitHub/GitLab only)
/comprehensive-review --read-back

# Review + stage both summary and findings as one draft on your own open PR
/comprehensive-review --post-summary --post-findings

# Review someone else's PR #42 locally (no remote posting)
/comprehensive-review --pr 42

# Review PR #42 and stage findings as a draft review (nothing published)
/comprehensive-review --pr 42 --post-findings

# Review PR #42 and publish findings immediately
/comprehensive-review --pr 42 --post-findings --publish

# Review PR #42 and post both summary and findings, published immediately
/comprehensive-review --pr 42 --post-summary --post-findings --publish

# Review against a non-default base
/comprehensive-review --base develop

# Security scan only (includes CVE check on changed dependency manifests)
/comprehensive-review --security-only

# Deep review — Opus for all agents + extended reasoning + CVE reachability triage
/comprehensive-review --depth deep
```

## Posting behavior

**`--post-findings` stages an editable draft by default** on GitHub (pending review) and GitLab (draft notes) — visible only to you until you edit and submit it yourself in the web UI. Add `--publish` to post immediately instead (today's pre-1.13.0 behavior; this is what CI/scripted use should pass). Bitbucket has no verified draft-create path, so `--post-findings` on Bitbucket always publishes a single PR comment, with a one-line notice that draft mode isn't available there yet.

| Scenario | Block A posted? | Block B posted/staged? | Review event |
|----------|----------------|----------------|--------------|
| No PR exists (default) | No | No | N/A |
| No PR exists + `--create-pr` | Yes — PR description | No | N/A |
| No PR exists + `--create-pr --post-findings` | Yes — folded into draft | Staged as draft review | N/A (no event on a draft) |
| No PR exists + `--create-pr --post-findings --publish` | Yes — PR description | Yes — inline review | `COMMENT` |
| Existing own PR (default) | No | No | N/A |
| Existing own PR + `--post-summary` | Yes — PR comment | No | N/A |
| Existing own PR + `--post-findings` | No | **Staged as draft review** (GitHub: pending review; GitLab: draft notes) — nothing published | N/A |
| Existing own PR + `--post-findings --publish` | No | Yes — inline review | `COMMENT` |
| Existing own PR + `--post-summary --post-findings` | Yes — folded into the same draft | Staged as draft review | N/A |
| Existing own PR + `--post-summary --post-findings --publish` | Yes — PR comment | Yes — inline review | `COMMENT` |
| `--pr <N>` (default) | No | No | N/A |
| `--pr <N>` + `--post-findings` | No | Staged as draft review on the external PR | N/A |
| `--pr <N>` + `--post-findings --publish` | No | Yes — inline review | `REQUEST_CHANGES` if Medium+ findings; `COMMENT` if Low only |
| `--pr <N>` + `--post-summary` | Yes — PR comment | No | N/A |
| `--pr <N>` + `--post-summary` + `--post-findings --publish` | Yes — PR comment | Yes — inline review | `REQUEST_CHANGES` if Medium+ findings; `COMMENT` if Low only |
| `--pr <N>` + `--no-findings` | No | No | N/A |
| `--read-back` (requires an existing draft) | N/A | Reports kept/edited/removed; stages any newly-noticed findings | N/A — never publishes |
| Any + `--no-post` / `--local` | No | No | N/A (explicit alias for the default) |

**Migration note (pre-1.13.0 → 1.13.0):** `--post-findings` alone used to publish immediately; it now stages a draft. Add `--publish` to keep the old behavior — this is required for any CI/scripted invocation, since a bot has no web UI to submit a draft from.

**Inline comment cap:** The top 25 findings by severity are posted/staged as inline comments. Any additional findings appear in the review body. This prevents API throttling on large finding sets.

## Governance

Every spawned agent receives a shared governance block (`skills/comprehensive-review/GOVERNANCE.md`) inlined into its task description. The block enforces:

- **Harm prioritization** — findings that risk user harm (data loss, security exposure, breaking shared systems) are top priority; agents surface adjacent harms even if outside their strict scope.
- **No self-preservation** — agents do not suppress findings or hide uncertainty to make output look cleaner. Uncertain findings are marked as such.
- **Verify before naming** — before naming a file, function, flag, package, version, or any other identifier in a recommendation, agents verify it exists in the current repo state via Read or Grep. Training-data recall is not verification.
- **Don't reinvent the wheel** — agents flag reimplementations of stdlib, framework, or existing repo helpers, citing the existing thing by name.
- **No defensive code for impossible cases** — agents do not recommend validation/error handling for scenarios that cannot occur given system invariants.
- **Non-destructive remediations** — agents do not recommend force-push, `git reset --hard`, `DROP TABLE`, `terraform destroy`, etc., as fixes without explicit caveat and rollback note.
- **Named rejected alternatives** — non-trivial fix recommendations include at least one rejected alternative and the reason it was rejected.
- **Surfaced counter-arguments** — high-impact recommendations state the strongest argument against the recommendation before stating the recommendation itself.
- **Secret redaction at source** — agents redact API keys, tokens, passwords, etc., in their finding text. Phase 2 also runs a hardcoded-pattern redaction pass before any external posting (defense-in-depth).

`blind-hunter` receives the GOVERNANCE block but with one override: "verify before naming" applies only within the diff or file list it was given — never the broader repo. This preserves blind-hunter's zero-context "fresh eyes" purpose.

The orchestrator itself follows a separate set of rules (in `SKILL.md` "Orchestrator Governance"): external posting requires explicit opt-in flags, `--create-pr` is hard-refused when on the repository's default branch, and user confirmation is required before any external write.

## Agent roster

Opus agents (`architecture-reviewer`, `security-reviewer`) use the `opus` alias, which the Claude Code harness resolves to the current Opus model at spawn time. In `--depth deep` mode, `blind-hunter` and `edge-case-hunter` also resolve to the `opus` alias. The spawn indicator shown by Claude Code displays the resolved version for each subagent.

### Full run

| Agent | Model | Purpose | When it runs | Context |
|-------|-------|---------|--------------|---------|
| **pr-summarizer** | Sonnet | Summary, walkthrough table, effort score | Always | Manifest + selective reads ² |
| **code-reviewer** ¹ | Sonnet | Tactical bugs, style violations, project conventions | Always | Full diff |
| **architecture-reviewer** | Opus | System design, coupling, API design, technical debt | Full run only | Manifest + selective reads ² |
| **security-reviewer** | Opus | OWASP-class security analysis, language-specific checks | Full run only | Manifest + selective reads ² |
| **silent-failure-hunter** ¹ | — | Silent failures, inadequate error handling | If diff has error-handling patterns | Relevant file slices |
| **pr-test-analyzer** ¹ | — | Test coverage gaps | If test files appear in the diff | Relevant file slices |
| **comment-analyzer** ¹ | — | Comment accuracy and rot | Full run only, if diff adds/modifies comments | Relevant file slices |
| **type-design-analyzer** ¹ | — | Type/struct/interface invariants | Full run only, if diff adds type definitions | Relevant file slices |
| **blind-hunter** | Sonnet | Context-free "fresh eyes" review: catches issues familiarity blinds other agents to | Full run only | Raw diff only (no project context) |
| **edge-case-hunter** | Sonnet | Mechanical path tracing: missing else/default, unguarded inputs, off-by-one, overflow, race conditions, resource leaks | Full run only | Manifest + selective reads ² |
| **adversarial-general** | Opus | Completeness gaps, missing defenses, operational blindness, documentation debt — what specialist agents are scoped not to cover | Full run only; skipped in TIER=tiny | Manifest + selective reads ² |
| **issue-linker** | Haiku | Finds referenced issues and related PRs/issues (GitHub only) | Full run only; skipped in `--pr` and when `--no-post`/`--local` is **explicitly** passed, and on non-GitHub repos | Commit log + branch + manifest |

### Deterministic checks

In addition to LLM agents, the skill runs deterministic checks when relevant files are in the diff:

| Check | Trigger | Runs in `--quick`? | Binary required |
|-------|---------|-------------------|----------------|
| **dependency-check** — queries [OSV.dev](https://osv.dev/) for known vulnerabilities in declared dependency versions | `go.mod`, `package.json`, `requirements*.txt`, or `composer.json` changed | Yes | (uses curl + jq) |
| **shellcheck** — shell script linting | `.sh` or `.bash` files changed | Yes | `shellcheck` |
| **semgrep** — polyglot SAST | Any source file changed | Yes | `semgrep` |
| **trufflehog** — secret scanning | Any file changed | Yes | `trufflehog` |
| **ruff** — Python linting | `.py` files changed | Yes | `ruff` |
| **golangci-lint** — Go static analysis | `.go` files changed | Yes | `golangci-lint` |
| **checkov** — IaC security scanning | `*.tf`, `*.tfvars`, `Dockerfile`, k8s YAML, CloudFormation, Azure ARM changed | Yes | `checkov` |
| **eslint** — JavaScript/TypeScript linting | `.js`, `.jsx`, `.ts`, `.tsx`, `.mjs`, `.cjs` files changed; only runs when an ESLint config is present | No | `eslint` (via `npx` or `node_modules/.bin`) |
| **hadolint** — Dockerfile linting | `Dockerfile`, `Dockerfile.*`, or `*.dockerfile` changed | No | `hadolint` |
| **kube-linter** — Kubernetes manifest linting | `.yaml`, `.yml`, or `.json` files containing `apiVersion` and `kind` fields | No | `kube-linter` |
| **phpcs** — PHP CodeSniffer | `.php` files changed; uses Drupal/DrupalPractice standard when available, falls back to PSR-12 | No | `phpcs` |
| **phpstan** — PHP static analysis | `.php`, `.module`, `.inc`, `.install`, `.theme` files changed | No | `phpstan` |
| **tflint** — Terraform linting | `.tf` or `.tfvars` files changed; runs per-directory | No | `tflint` |

No API key required for any check. All static analyzers are **opportunistic** — if the binary is not installed, the check is silently skipped with no error. Install as needed: `brew install shellcheck hadolint kube-linter tflint`, `pip install semgrep ruff checkov`, `go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest`, [trufflehog releases](https://github.com/trufflesecurity/trufflehog/releases), `npm install -g eslint`, `composer global require squizlabs/php_codesniffer phpstan/phpstan`. Findings appear in Block B with the tool name as source (e.g., `[shellcheck]`, `[eslint]`).

### `--quick` mode

Skips: architecture-reviewer, security-reviewer, blind-hunter, edge-case-hunter, comment-analyzer, type-design-analyzer, issue-linker.
Still runs: pr-summarizer, code-reviewer, triggered silent-failure-hunter / pr-test-analyzer, and the CVE check if manifest files changed.

¹ From the `pr-review-toolkit@claude-plugins-official` plugin.
² For small diffs (under 300 lines), the full diff is passed inline instead.

## Language profiles

The skill ships per-language context profiles for 19 languages: Go, Python, TypeScript, JavaScript, PHP, Ruby, Rust, Java, C++, Shell, C#, Kotlin, Swift, Scala, Lua, Perl, SQL, Terraform, and YAML. When a language is detected in the diff, the corresponding profile is automatically injected into the relevant agents' task descriptions. Profiles contain:

- **Do-NOT-Flag idioms** — language patterns that look like bugs but are idiomatic (e.g., Go's blank identifier, Python's `pass`, etc.)
- **Common bugs** — patterns the LLM should actively look for
- **Language-specific security guidance** — e.g., SQL injection vectors specific to each language
- **Idiomatic trust boundaries** — what counts as safe vs. untrusted in this ecosystem

**blind-hunter does not receive language profiles** — its zero-context constraint is preserved.

To add a language profile, create `skills/comprehensive-review/language-profiles/<lang>.md` and add the language extension to the detection block in SKILL.md Phase 0.

## Symbol context enrichment

On all full runs except TIER=tiny (<50 lines, ≤3 files), the skill automatically extracts symbol references from the diff and looks up their definitions across the repo using Claude Code's `Grep` tool (backed by ripgrep). The results are injected as a `<symbol-context>` block into eligible agents, giving them cross-file definition context without reading the entire codebase.

This is the Claude Code equivalent of ai-pr-review's Epic 3-A (treesitter + ripgrep context enrichment) — implemented using Claude Code's native tools rather than Python + optional dependencies.

**Cost note:** enrichment adds ~1–3K tokens per eligible agent (roughly 8–16K tokens total on a full run). Use `--no-enrich-context` to disable if you want to reduce token cost or if Grep calls become slow on very large repos.

Agents that receive symbol context: architecture-reviewer, security-reviewer, adversarial-general, edge-case-hunter, code-reviewer.
Agents excluded: blind-hunter (zero-context constraint), pr-summarizer (does not need definitions), all pr-review-toolkit agents (externally managed).

## Suppressions

The skill ships a default suppressions file (`skills/comprehensive-review/suppressions.json`) and supports per-repo overrides at `.claude/comprehensive-review/suppressions.json`.

Each suppression rule has:
- `id` — unique identifier
- `reason` — human-readable explanation
- `match.pattern` — regex applied to finding text
- `verify` (optional) — ecosystem to call before suppressing (see below)

**Verify-before-suppress:** Rules with a `verify` field call an external registry API to confirm the flagged version actually exists before suppressing. If the registry returns 2xx, the finding is suppressed. If it returns 404 or errors, the finding is kept (fail-open). Supported ecosystems:

| `verify` value | Registry called |
|---------------|----------------|
| `github-release` | GitHub Releases API |
| `npm` | registry.npmjs.org |
| `pypi` | pypi.org |
| `go-module` | proxy.golang.org |
| `cargo` | crates.io |
| `docker-hub` | hub.docker.com |
| `ruby-org` | cache.ruby-lang.org |

Use `--no-suppress` to disable all suppression rules for a run (useful for audits).

## Confidence filtering

All custom findings agents emit a `confidence` integer (0–100) per finding reflecting certainty that the finding is genuine rather than a false positive. The `--min-confidence` flag (default: 75) filters out findings below the threshold **before** suppression rules are applied.

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

This block is consumed by the Phase 2 pipeline for normalization, confidence filtering, suppression, and dedup. The human-readable markdown section remains for inspection; the `json-findings` block drives the structured pipeline.

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
~/.claude/agents/adversarial-general.md
```

The `pr-review-toolkit` plugin installs its agents to `~/.claude/plugins/` automatically.

## Cost expectations

Run this skill on **Sonnet** — the orchestrator does structured workflow coordination, not deep reasoning. Opus is reserved for the internally-spawned `architecture-reviewer` and `security-reviewer` agents.

| Mode | Typical cost |
|------|------------:|
| `--quick` | **~$0.25** |
| Full run (Sonnet orchestrator) | **~$0.50–$1.25** |

**Cost-saving options:**
- `--quick`: skips architecture-reviewer, security-reviewer, and four other agents. Roughly 60–80% cheaper.
- `--depth normal` (default): Opus reserved for 2 agents. `--depth deep` promotes 2 more to Opus and roughly doubles cost.
- `--output-file <path>`: writes the report to disk during the review session, avoiding a separate follow-up request against a large accumulated context.

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
- **Token utilization table:** Phase 5 always prints a per-agent breakdown of total tokens and estimated USD cost, so you can see where budget is going without running `/cost`.

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

## Contributing

The deterministic bash helpers in `skills/comprehensive-review/scripts/` and `tests/` have a [bats](https://github.com/bats-core/bats-core) test suite:

```bash
# Install bats (macOS)
brew install bats-core

# Run all tests
bats tests/*.bats
```

Tests cover: `parse_go_mod` replace-directive ordering, TruffleHog invocation modes (including allowlist suppression), gate evaluation logic, golden orchestration contracts (SKILL.md structural integrity, PROVIDERS.md correctness, SEVERITY.md contract), and all static analyzer scripts (eslint, hadolint, kube-linter, phpcs, phpstan, tflint). All 150 tests are offline (no network, no Claude invocation).

## Acknowledgments

The `blind-hunter` and `edge-case-hunter` agents are adapted from concepts in the
[BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) project by Brian "BMad" Madison
(BMad Code LLC), released under the [MIT License](https://github.com/bmad-code-org/BMAD-METHOD/blob/main/LICENSE).

BMAD's code review workflow uses parallel adversarial review layers — a context-free "Blind Hunter"
and a path-tracing "Edge Case Hunter" — which we adapted into our agent architecture. Our
implementations differ from BMAD's originals: we use structured severity output, omit the
minimum-findings mandate, and integrate tightly with our manifest and context-passing strategy.

## Updating

```
/plugins update comprehensive-review@tag1consulting
```

## Uninstalling

```
/plugins uninstall comprehensive-review@tag1consulting
```

For manual installs, remove `~/.claude/plugins/cache/tag1consulting/comprehensive-review`, then remove the `comprehensive-review@tag1consulting` entry from `~/.claude/plugins/installed_plugins.json` and `enabledPlugins` in `~/.claude/settings.json`.
