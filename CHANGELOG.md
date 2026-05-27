# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.8.11] - 2026-05-27

### Added

- New `GOVERNANCE.md` directive: **Cite evidence in the finding.** Findings must reference the specific code that exhibits the problem (snippet, symbol, or pattern at `file:line`) — the json-findings location fields are not the citation. Intended to reduce hallucinated structural findings; effectiveness has not been measured.
- New `GOVERNANCE.md` directive: **Refuse incoherent input.** If a diff contradicts its own commit message or claims to fix something it doesn't touch, agents surface that as a top-level finding rather than reviewing line-by-line as if coherent.
- New Orchestrator Governance directive in `SKILL.md`: **Cite the observed result, not the action taken.** Phase 4/4b/5 success claims reference the provider-returned URL, ID, or status — not just the fact that an API call was attempted.
- Phase 4/4b/5 capture-variable wiring to back the new directive with mechanism rather than text. Phase 4 PR/MR creation captures provider stdout/exit into `CREATED_PR_URL`/`CREATED_PR_ERROR`; Phase 4 comment posting captures `POSTED_COMMENT_REF`/`POSTED_COMMENT_ERROR`; Phase 4b inline review posting captures `POSTED_REVIEW_URL`/`POSTED_REVIEW_ID`/`INLINE_POSTED_COUNT`/`INLINE_FAILED_COUNT`/`POSTED_REVIEW_ERROR`; Phase 5 worktree cleanup verifies removal via `[[ -e "$WORKTREE_PATH" ]]` and sets `WORKTREE_REMOVED`; Phase 5 claude-mem POST captures `MEM_HTTP_STATUS` via `curl -w '%{http_code}'` and only reports success on 2xx. Phase 5 terminal output cites these captured values rather than asserting success from the fact that an API call was invoked. Failure paths are reported plainly when capture variables are empty.
- BLIND_HUNTER_NOTE extended to scope the new "Refuse incoherent input" directive to incoherence visible within the diff itself (e.g., a hunk that calls a symbol the same diff just deleted), preserving blind-hunter's zero-context constraint.

### Fixed

Robustness fixes to the Phase 4/4b/5 capture-variable patterns, addressing AI review findings on PR #79:

- **`gh pr create` URL extraction:** replaced `grep -Eo 'https://...'` over combined stdout/stderr (which could capture push-remote URLs or warning URLs) with a two-step pattern: run `gh pr create` for its exit code, then `gh pr view --json url --jq '.url'` for an unambiguous PR URL. Same pattern applied to `glab mr create` → `glab mr view --output json` → `.web_url`.
- **`POSTED_COMMENT_REF` empty-on-success false-failure:** exit code is now the primary success signal for `gh pr comment` / `glab mr comment`. An empty URL on RC=0 is reported as `(posted; URL not reported by gh)` rather than treated as failure — preventing a false failure report and a duplicate comment on retry.
- **`INLINE_POSTED_COUNT` parsed from response, not request:** GitHub silently drops inline comments whose target line is outside the diff (despite the Phase 4b step 1 valid-line filter — GitHub's own validation is stricter for renamed files, large hunks, etc.). The count is now parsed from `(.comments // []) | length` of `REVIEW_RESPONSE`. A delta vs the request length triggers a "GitHub accepted the review but dropped <N> inline comment(s)" warning.
- **GitLab inline-warning placeholder:** the warning log now uses `printf` with `${THREAD_RESPONSE:-no thread ID returned}` instead of a literal `<error or ...>` placeholder, so warnings carry the actual response content.
- **`git worktree remove` stderr capture:** previously used `2>/dev/null || true` and then synthesized `WORKTREE_CLEANUP_ERROR="path still exists at ..."` which never carried the actual git error. Now captures stderr into `WORKTREE_REMOVE_ERR` before the path-existence check; `WORKTREE_CLEANUP_ERROR` falls back to the captured stderr.
- **`MEM_RESPONSE_FILE` mktemp guard + response body preserved:** `mktemp` now falls back to `/dev/null` on failure (preventing curl from writing to an empty-string path). The response body is read into `MEM_RESPONSE_BODY` before the file is deleted, so server error bodies survive for diagnostics when `MEM_SAVED=false`.

### Changed

- Aligned plugin governance with refactored `~/.claude/CLAUDE.md` (Outcome Verification, Disagreement & Alternatives sections). Items deemed out of scope for a per-run review tool (Session Self-Audit, Active Guardrails, Checkpoint Triggers list, Pre-Claim/Pre-Action Check) were intentionally not imported.
- Updated `CLAUDE.md` Governance directives summary to enumerate the two new agent-side directives under the Honesty bullet and to reflect the extended BLIND_HUNTER_NOTE scope.

---

## [1.8.10] - 2026-05-27

### Changed

- Removed all `--help` / `-h` flag handling from `SKILL.md`. Every implementation approach tried in v1.8.1–v1.8.9 proved unreliable (see note below). `HELP.md` remains as reference documentation accessible in the repo and README.
- Replaced "CodeRabbit-style" wording with neutral language across `SKILL.md`, `HELP.md`, `README.md`, `plugin.json`, and `CLAUDE.md`.

---

## [1.8.9] - 2026-05-27

### Fixed

- Restored eager `!`-prefixed Pre-flight Context injection in `SKILL.md`. These commands run at skill load time before LLM invocation, injecting real repo/branch/diff data into context. The `!` prefix was accidentally removed during the v1.8.x `--help` refactoring, causing the LLM to treat `SKILL.md` as a document to render rather than a workflow to execute.
- Restored imperative opening sentence ("Run a full PR/MR review…") that was lost in the same refactoring.

---

## [1.8.8] - 2026-05-27

### Changed

- Moved `--help` redirect instruction to the top of the `SKILL.md` H1 heading as a diagnostic test — restored the v1.6.0 instruct-stop pattern verbatim to determine whether failure was body-size dependent. Confirmed: the pattern fails at v1.8.x body size (~1,400 lines); it worked in v1.6.0 at ~200 lines.

---

## [1.8.7] - 2026-05-27

### Added

- Introduced a dedicated `comprehensive-review-help` sibling skill using `disable-model-invocation: true` to serve `--help` output without LLM involvement.

### Changed

- Replaced `--help` flag in the main skill with a redirect to `/comprehensive-review-help`.

### Notes

`disable-model-invocation: true` suppressed all output in Claude Code 2.1.152 — the skill ran silently with no output. This approach was abandoned; `comprehensive-review-help` remains as a placeholder stub.

---

## [1.8.6] - 2026-05-27

### Fixed

- Removed duplicate inline flag documentation from `SKILL.md` that gave the LLM fallback content to render when the `--help` injection block was present, causing flags to appear in output alongside or instead of `HELP.md` content.

---

## [1.8.5] - 2026-05-27

### Fixed

- Strengthened `--help` stop instruction to include sentinel markers (`===HELP-START===` / `===HELP-END===`) to give the LLM an unambiguous literal anchor for the help block boundaries.

---

## [1.8.4] - 2026-05-27

### Changed

- Replaced LLM-executed bash snippet for `--help` with dynamic context injection using the `!`-prefix syntax. The injection command guards on `$ARGUMENTS` so it emits nothing on normal runs. Rationale: injection runs at skill load time before the LLM sees the file, making it deterministic rather than LLM-discretionary.

---

## [1.8.3] - 2026-05-27

### Fixed

- Rewrote `--help` bash snippet as an explicit `Bash` tool call instruction to prevent the LLM from shortcutting to inline flag docs instead of running the command.

---

## [1.8.2] - 2026-05-27

### Fixed

- Added Phase 0 step to read and display `HELP.md` when `--help` is present, replacing the previous stub that had no implementation.

---

## [1.8.1] - 2026-05-27

### Fixed

- Deferred eager `!`-prefixed pre-flight shell commands (branch detection, diff stats) to after the `--help` check in Phase 0, preventing them from executing and dumping output before help text could be shown.

> **Note on v1.8.1–v1.8.9:** All ten patch releases were attempts to implement a working `--help` flag. Each was tagged and pushed to the marketplace as a candidate, then superseded within the same session when testing revealed it didn't work. The root cause: the LLM receives the entire ~1,400-line `SKILL.md` as context; no stop instruction embedded within it reliably prevents the LLM from processing subsequent content at that body size. v1.8.10 accepts this constraint and removes the flag entirely. See the [v1.8.10 release notes](https://github.com/tag1consulting/claude-comprehensive-review/releases/tag/v1.8.10) for the full account.

---

## [1.8.0] - 2026-05-26

### Added

**Shared governance directives for all custom agents.** A new `skills/comprehensive-review/GOVERNANCE.md` file is loaded once in Phase 0 (step 9) and inlined into every custom agent's task description in Phase 1. Directives cover:

- Harm prioritization (First Law framing)
- No self-preservation (don't suppress findings or hide uncertainty)
- Verification before naming files, functions, flags, packages, versions
- Don't reinvent the wheel (flag reimplementations of stdlib/framework/repo helpers)
- No defensive code for impossible cases
- Non-destructive remediations only (no force-push, `reset --hard`, `DROP TABLE`, etc., as fixes without explicit caveat)
- Named rejected alternatives for non-trivial recommendations
- Surfaced counter-arguments before high-impact recommendations
- Secret redaction at source

All 7 custom agents (`pr-summarizer`, `issue-linker`, `security-reviewer`, `architecture-reviewer`, `adversarial-general`, `edge-case-hunter`, `blind-hunter`) receive the GOVERNANCE block. **blind-hunter exception:** a `BLIND_HUNTER_NOTE` line clarifies that "verify before naming" for blind-hunter applies only within the diff or file list it was given — never the broader repo. This preserves the zero-context constraint while keeping every other directive in force.

**Architecture-reviewer scope-creep lens.** New review section (#8) explicitly hunts for single-use abstractions, hypothetical-future hooks, and reimplementations of existing primitives. Three similar lines is better than a premature abstraction.

**Phase 2 secret-redaction backstop.** New step 2f applies a hardcoded-pattern redaction pass to all finding text and Block A summary text before any external posting. Patterns cover GitHub tokens (`ghp_`/`gho_`/`ghs_`/`ghu_`/`ghr_`), Slack tokens (`xox[baprs]-`), AWS access keys (`AKIA*`), Bearer/Basic auth headers, and assignment patterns for `password=`/`token=`/`api_key=`/`secret=`/`aws_secret_access_key=`. This is defense-in-depth for the agent-source redaction in `GOVERNANCE.md`, not a replacement.

**Orchestrator governance section in SKILL.md.** New section near the top of `SKILL.md` documents the orchestrator-side rules: external comms gated by explicit flags, mandatory user-confirmation prompts before posting, and the new default-branch refuse for `--create-pr`.

**`--create-pr` default-branch hard refuse.** Phase 4 now refuses `--create-pr` when the current branch matches the repository's default branch (queried from the provider via `gh repo view` / `glab api projects/...` / Bitbucket `mainbranch.name`, with `main`/`master`/`develop`/`trunk` as a conservative fallback when the lookup fails). Exits non-zero with a clear error directing the user to check out a feature branch. No override flag.

### Changed

- `security-reviewer.md`, `adversarial-general.md`: brief framing additions noting that the `GOVERNANCE` block is authoritative when present.
- `architecture-reviewer.md`: new "Scope creep and over-engineering" review lens (#8).
- Agent task-description directive table: `GOVERNANCE` added as a new directive consumed by all 7 custom agents.

### Notes

The shared-file approach was chosen over per-agent inlining to make future directive changes single-source. Token cost is ~400 tokens × 7 spawned agents ≈ 2.8k tokens per full review — acceptable given the governance value and the avoidance of drift across 7 separate agent files.

## [1.7.1] - 2026-05-20

### Fixed
- **Tab completion doubled name** — restored `name: comprehensive-review` to SKILL.md frontmatter. Without this field Claude Code falls back to the skill directory name, producing `/comprehensive-review:comprehensive-review` in tab completion. The `name:` field was incorrectly removed in v1.6.x under the belief it was unsupported.

---

## [1.7.0] - 2026-05-20

### Added

**10 new language profiles** ported from ai-pr-review v0.9.1:
- C# (`csharp.md`) — nullable reference types, LINQ pitfalls, async void, dispose patterns
- JavaScript (`javascript.md`) — prototype pollution, event loop, CommonJS vs ESM
- Kotlin (`kotlin.md`) — null safety, coroutine scope leaks, sealed classes
- Lua (`lua.md`) — 1-based indexing, global-by-default, coroutine edge cases
- Perl (`perl.md`) — context sensitivity, sigil typing, regex gotchas
- Scala (`scala.md`) — implicit resolution, variance, Future execution context
- SQL (`sql.md`) — injection patterns, index usage, NULL semantics
- Swift (`swift.md`) — ARC retain cycles, optional force-unwrap, actor isolation
- Terraform (`terraform.md`) — state drift, resource cycles, provider version pinning
- YAML (`yaml.md`) — Norway problem, implicit type coercions, anchor/alias pitfalls

**Symbol context enrichment** (Phase 0c): on by default for full runs at TIER=small and TIER=medium.
Extracts symbol references from the diff, locates their definitions via `Grep` (ripgrep-backed),
reads ±5 lines of surrounding context, and injects a `<symbol-context>` XML block into eligible
agents. Disable with `--no-enrich-context`. Equivalent to ai-pr-review's Epic 3-A
(treesitter + ripgrep context enrichment) implemented using Claude Code's native tools.

**Per-agent conditional gates** ported from ai-pr-review v0.9.0 `agents/gates.py`:
- `has_control_flow` — skips edge-case-hunter when no branching constructs (if/for/while/match/try) appear in added lines
- `has_code_or_infra` — skips architecture-reviewer on pure docs/meta-only PRs (`.md`, `.rst`, CHANGELOG, README, LICENSE, etc.)
- `has_security_patterns` — extended security keyword and file-path regex to match ai-pr-review's broader pattern set
- `has_error_patterns` — existing silent-failure-hunter trigger now unified with gate framework

**PR narrative context** (Phase 0 step 6): full commit bodies (via `git log --no-merges --format='%H%n%s%n%n%b%n'`)
and PR description body (in `--pr <N>` mode) are now passed to pr-summarizer, code-reviewer,
architecture-reviewer, security-reviewer, adversarial-general, and edge-case-hunter. Reduces
false positives from agents flagging things the author has already explained in commit messages.

**Merge-commit stripping**: commit log now uses `--no-merges` to exclude base-branch merge commits
(e.g., periodic `main → feature` syncs), so agents see only the intentional work.

**Missing ruby-org suppression rule**: added `version-post-knowledge-cutoff-ruby` suppression rule
to `suppressions.json`. The `ruby-org` verify ecosystem was already implemented in SKILL.md Phase 2d
but had no corresponding rule.

**CHANGELOG.md**: this file, backfilled from v1.5.0.

### Changed
- Phase 0 language detection table now explicitly maps all 19 language names to their file
  extensions, ensuring consistent profile loading for the 10 new languages
- agent directive table updated with `PR_NARRATIVE` and `SYMBOL_CONTEXT` directives
- `--no-enrich-context` flag added to HELP.md

### Removed
- **`install.sh`** — removed entirely. The script accumulated five fix commits in v1.6.x trying
  to resolve plugin-cache namespace shadowing between `tag1consulting-local/` (local install) and
  `tag1consulting/` (marketplace install). The root cause was having two install paths at all.
  The marketplace install (`/plugins install comprehensive-review@tag1consulting`) handles
  the same cache path, pr-review-toolkit dependency, and settings registration — with no
  jq/curl prerequisites or shell error-handling complexity. End users and contributors now
  use the same single install path.
- SKILL.md `tag1consulting-local` fallback paths for `language-profiles/`, `suppressions.json`,
  and `scripts/` repointed to `tag1consulting/` (no behavioral change for marketplace installs).

---

## [1.6.1] - 2026-05-20

### Fixed
- **Agent namespace prefix** — all owned agents now use `comprehensive-review:` prefix in `subagent_type` values (e.g., `comprehensive-review:security-reviewer`) to satisfy Claude Code's plugin install path resolution. Fixes #63 where agents dispatched in plugin-install mode were resolving to the wrong (or missing) agent file.
- **SKILL.md fallback paths** — replaced hardcoded `--local` install paths with glob patterns that match any plugin install version, fixing agent resolution for marketplace installs and future version bumps.
- **`install.sh` bootstrap** — `installed_plugins.json` is now auto-initialized with the correct v2 seed format if absent, eliminating the chicken-and-egg failure on first-time installs. (Note: `install.sh` was subsequently removed in v1.7.0; the `/plugins install` path handles this automatically.)

---

## [1.6.0] - 2026-05-08

### Added
- **checkov IaC security scanner** integration (`scripts/run-checkov.sh`) — scans changed Terraform,
  Kubernetes/Helm YAML, Dockerfiles, CloudFormation, and Azure ARM templates in Phase 1b
- **TruffleHog test-file demotion**: unverified secret detections in test/fixture/example paths are
  demoted to Low/confidence-40 with `[test file — likely mock data]` tag
- **`ruby-org` verify ecosystem** support in SKILL.md Phase 2d (cache.ruby-lang.org HEAD request)
- **Knowledge-cutoff guardrails** added to adversarial-general agent; standardized across all six
  finding-producing agents (architecture-reviewer, security-reviewer, blind-hunter, edge-case-hunter,
  adversarial-general)

### Changed
- ai-pr-review v0.7.0 parity: shared prompt trailer semantics, agent scope refinements

---

## [1.5.0] - 2026-04-23

### Added
- **adversarial-general agent** — holistic "what's missing" review covering completeness, operational
  readiness, documentation debt, and deployment/rollback concerns. Adapted from BMAD-METHOD (MIT License).
- **Suppression framework** (`suppressions.json`): 6 verify-gated rules (github-release, npm, pypi,
  go-module, cargo, docker-hub) + 2 unconditional rules. Global + per-repo local overrides via
  `.claude/comprehensive-review/suppressions.json`
- **9 language profiles**: Go, Python, TypeScript, PHP (+ Drupal patterns), Ruby, Rust, Java, C++, Shell
- **claude-mem integration** (opt-in with auto-detection): prior review history passed to
  architecture-reviewer and security-reviewer; review summary saved to persistent memory
- **`--depth deep` flag**: promotes blind-hunter and edge-case-hunter to Opus, enables EXTENDED_THINKING
  for architecture-reviewer and security-reviewer, adds CVE reachability triage pass
- **`--no-suppress` and `--min-confidence` flags**
- **TIER=tiny auto-selection** (<50 lines AND ≤3 files): pr-summarizer drops to Haiku; Opus agents
  conditional on infra/security-path triggers
- **TIER=medium context strategy**: custom agents receive file manifest + selective `git diff -- <file>`
  reads; toolkit agents receive diff slices

### Changed
- All agents now use namespace-qualified `subagent_type` values (e.g., `pr-review-toolkit:code-reviewer`)
- Issue-linker returns NONE for non-GitHub providers (avoids false GitHub API calls on GitLab/Bitbucket)
