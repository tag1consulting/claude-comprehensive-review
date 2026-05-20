# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
