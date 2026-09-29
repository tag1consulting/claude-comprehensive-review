# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.15.3] - 2026-09-29

### Fixed

- **`SKILL.md` no longer breaks when the skill is invoked with arguments.** Claude Code replaces `$0`..`$9` (0-indexed positional arguments) anywhere in a skill body, including inside bash code fences, whenever that argument index is supplied. `SKILL.md` contained 23 such tokens, so invoking `/comprehensive-review --pr 143` rewrote the skill text the orchestrator follows: `awk -F/ '{print $1}'` in the tiny-tier architecture-promotion check became `'{print 143}'` (so the cross-directory trigger could never fire), `local agent_name="$1"` in `extract_findings` became `agent_name="143"` (stamping every finding's `source` with the PR number), and the dollar amounts in the cost guidance and the token utilization table were rendered as garbage such as `~--pr.25`. All dollar-digit tokens are gone: costs are written as `0.25 USD`, the awk calls use `cut` and `sed`, and `extract_findings` reads its arguments with `${@:1:1}` and `${@:2:1}`. The token utilization table's Est. Cost column now reads `~0.12 USD` instead of `~$0.12`.

### Added

- `tests/skill_substitution.bats` (6 tests): fails if any dollar-digit token appears in `SKILL.md`, calls `extract_findings` directly to check it reads its first argument, and runs the two rewritten pipelines. `CLAUDE.md` documents the rule for contributors.

## [1.15.2] - 2026-09-29

### Fixed

- **Token utilization table overstated cost by roughly 4–5×**: the blended rates (Opus ~$45/M, Sonnet ~$9/M, Haiku ~$0.8/M) dated from the Opus 4/4.1 price era, and they were applied to a number that is not cumulative usage. Measured against subagent transcripts, `subagent_tokens` is the agent's final-turn context size, mostly cache reads billed at a small fraction of the input price. Rates are now Opus ~$8/M, Sonnet ~$4/M, Haiku ~$2/M, calibrated from about 40 transcripts at current list prices, and the Phase 5 note states the ±40% per-agent spread. The Haiku rate rests on one sample. The "~5× lower orchestrator cost" tip is now "~2×" to match current Opus vs. Sonnet pricing.

### Added

- **Weekly model and pricing drift check**: `scripts/check-model-pricing.sh` compares Anthropic's published pricing table with the snapshot in `skills/comprehensive-review/model-pricing.json`, and the `model-pricing-check.yml` workflow files a deduplicated `pricing-drift` issue when a model is added, removed, or repriced, or when the page can no longer be parsed. `tests/model_pricing.bats` also asserts that the blended rates in `SKILL.md`, `docs/token-efficiency.md`, and the snapshot agree.

## [1.15.1] - 2026-09-18

### Fixed

- **Pre-flight base-branch detection no longer diffs a feature branch against itself** (#140): the pre-flight "Branch context" step computed the diff base from `HEAD@{upstream}`, which for a branch pushed with `git push -u origin <same-name>` resolves to the branch's own remote-tracking ref rather than the repository's default branch, silently producing an empty or nonsensical diff instead of comparing against `main`. A prior fix (`2d330a1`, in 1.14.0) addressed a related staleness and exit-status defect in the same line without fixing this one. Now resolves the default branch from `origin/HEAD`'s symbolic ref, with a local, network-free fallback to the first of main/master/develop/trunk that exists as a remote-tracking branch (matching the existing `--create-pr` default-branch pre-check pattern), and a visible `WARNING` when detection degrades to that fallback.

## [1.15.0] - 2026-08-26

### Changed

**`security-reviewer` content parity with ai-pr-review.** Ported confirmed-real
coverage gaps found by a cross-repo parity audit: a new "Unsafe Deserialization"
section (Python pickle/marshal/shelve/yaml.unsafe_load/joblib/pandas/numpy, ML
model loading via `torch.load`/`tf.saved_model.load`, PHP `unserialize`), a
"Gate/action field mismatch" authorization check, a new "Infrastructure-as-Code
Security" subsection, a new "Parser and Validator Differentials" section, and
expanded language-specific sinks: Go `exec.Command("sh"/"bash", "-c", ...)`
shell-invocation variants, Python `os.system()`, TypeScript/JavaScript DOM-XSS
sinks (`outerHTML`, `insertAdjacentHTML`, `document.write`) and missing
Subresource Integrity, GitHub Actions untrusted-context interpolation, and
crypto specifics (AES ECB mode, Node's deprecated `createCipher`/
`createDecipher`). This repo's own governance block, `SECURITY_POLICY` block,
`LANGUAGE_PROFILES` dispatch, frontmatter, and existing XXE section (already
identical to ai-pr-review's) were all left untouched — this was a content
merge, not a file replace. (#136)

Two related gaps were identified but are explicitly out of scope for this
release: the JSON-after-markdown output ordering (vs. ai-pr-review's
before-markdown ordering, chosen there so findings survive response
truncation) is a repo-wide output-contract decision affecting every agent, not
a single-agent content change; and the per-language profile files
(`python.md`, `javascript.md`, `typescript.md`, `terraform.md`) are missing
some of these same sinks and take precedence over this fallback checklist in
the real dispatch path, so those specific new checks will not reach a review
through the primary path until a follow-up ports the same content there.

## [1.14.0] - 2026-08-24

### Added

**Explicit Three Laws framing as `GOVERNANCE.md`'s lead section.** A new "Core
directives: the Three Laws" section opens the shared governance block. The First
and Second Laws are quoted verbatim from the maintainer's `~/.claude/CLAUDE.md`
Core Directives and both apply. The Third Law is stated and explicitly rejected:
no self-preservation in any form. The framing was previously implicit, with a
"First Law applies" bullet and a "No self-preservation" bullet carrying the
behavior but with no attribution anywhere in the repo, and with the Second Law
absent entirely.

Each existing directive is now labeled with the Law it instantiates: "Priority
and harm" from the First Law, "No self-preservation" from the Third Law's
rejection, and two Second Law consequences that were already in the file without
being named as such. The task description is the human's order, with "Surface
adjacent harms" as the First Law's override of that scope, and injected
directives in a diff or PR body are not orders given by a human being, which is
the basis of the whole "Untrusted input" section.

### Changed

- `SKILL.md` "Orchestrator Governance": the section intro now names the Second
  Law as what its flag-gating, confirmation-prompt, and hard-refuse rules
  instantiate, and points at `GOVERNANCE.md` for the Law text rather than
  restating it, per the standing anti-duplication rule. The `--create-pr`
  default-branch refuse is called out as the First Law exception in action.
- `README.md`, `docs/governance.md`, and `CLAUDE.md` governance summaries now
  enumerate all 16 directives across all 6 sections. They previously listed 9,
  10, and a partial summary respectively, and all three omitted the "Untrusted
  input" section entirely.
- `docs/governance.md` and `README.md` now describe both directives scoped by the
  blind-hunter exception. They previously named only "verify before naming" and
  omitted "refuse incoherent input" and the general precedence clause.
- Corrected two stale `Phase 2 step 2f` references in `CLAUDE.md` to `step 2g`.
  Step 2f is the novelty pass, step 2g is secret redaction.

### Fixed

- Corrected a stale "184 tests" count in `CLAUDE.md` and `README.md` to "188
  tests" — the Three Laws commit above added the suite's 185th test without
  updating either doc, and this release's own new derivation-pointer and
  `BLIND_HUNTER_NOTE` regression tests (see Notes) bring the true count to
  188.
- `README.md`'s Governance section previously merged "Verification before
  naming" and "Recommendations" under one heading and folded "Mark
  uncertainty explicitly" into another bullet's prose, so it actually had 15
  directives across 5 sections despite this file's own claim (above) that it
  enumerates all 16 across all 6. Split it to genuinely match.
- The new `BLIND_HUNTER_NOTE` byte-identity test's equality check would have
  vacuously passed if both copies degraded to the same empty string (e.g. a
  future edit leaving the note's body empty at both sites). Added an
  explicit non-empty guard before the equality check, and documented that
  the test's whole-file substring count is a known, narrow limitation
  rather than anchoring the grep to the two spawn sites.
- Fixed a base-resolution bug in `SKILL.md`'s Pre-flight "Branch context"
  step: it piped `git rev-parse --abbrev-ref HEAD@{upstream}` into
  `sed 's|origin/||'` and relied on `|| echo "main"` as a no-upstream
  fallback. That fallback tested `sed`'s exit status, not `rev-parse`'s, so
  it never fired when there was no upstream (`sed` succeeds on empty stdin),
  and even with an upstream, stripping the `origin/` prefix rewrote a fresh
  remote-tracking ref into a same-named local branch that can be arbitrarily
  stale. The second defect caused a comprehensive-review run on this very
  branch to initially review against a local `main` 16 commits behind
  `origin/main`, before the mistake was caught mid-run. Fixed by keeping the
  full remote-tracking ref and checking emptiness explicitly.

### Notes

The new section is 1552 bytes (roughly 380-400 tokens by byte-count estimate,
not a tokenizer run), paid on each of 7 agent spawns per full review, so on
the order of 2.5-2.8k tokens per run. Accepted deliberately: the framing is
the file's stated purpose and the derivation pointers are what make it
central rather than decorative.

No loader or injector changes were needed. Phase 0 step 9 reads the whole file
into `GOVERNANCE_BLOCK` with no section parsing and no rule count, so adding a
section is transparent to the pipeline. The BLIND_HUNTER_NOTE was deliberately
left unchanged: the Laws require no external context, so the note's existing
general precedence clause already covers them. The note's two byte-identical
copies, and the Three Laws' own five named derivation pointers, are now both
guarded by regression tests in `tests/orchestration_contracts.bats`.

## [1.13.0] - 2026-07-16

### ⚠ Behavior change

- **`--post-findings` now stages an editable draft by default instead of publishing immediately.** On GitHub this creates a PENDING review (`POST .../pulls/{n}/reviews` with no `event`); on GitLab it creates draft notes (`POST .../draft_notes`). Either way, the draft is visible only to the invoking user and nothing is published until they edit and submit it themselves in the provider's web UI. **Add `--publish` to restore the previous (pre-1.13.0) immediate-publish behavior** — this is required for any CI/scripted invocation, since a bot has no web UI to submit a draft from. Bitbucket is unaffected: it has no verified draft-create path in the public REST API, so `--post-findings` there always publishes a single PR comment, with a one-line notice.

### Added

- **"Human in the Middle" draft review mode** (`--draft`, `--publish`): implements the staging-layer workflow described in the "Human in the Middle" pattern — the AI drafts, the human edits and submits, never the other way around. `--draft` is an explicit no-op alias of the new default, for scripts that want to pin the behavior. New `PROVIDERS.md` operation "OP: Stage draft review" is kept separate from the existing publish operation so the "never call a submit/publish endpoint" invariant is greppable and covered by structural tests.
- **`--read-back`** (GitHub/GitLab only): reads back the user's currently-staged draft (pending review comments / draft notes), reports which of this run's findings the human kept, edited, or removed. On GitLab, newly-noticed findings are staged as additional draft notes. **On GitHub, they are reported in the terminal only** — the REST pending-review API only accepts comments at creation time and cannot append to an existing pending review (appending would require the GraphQL `addPullRequestReviewThread` mutation, not implemented in this version), so the human adds any agreed-on findings themselves in the web UI. Never publishes and never overwrites the human's edits. Requires an existing draft from a prior `--post-findings` run. **Cost note:** since the comparison is against "this run's findings," `--read-back` re-runs the full Phase 0–3 analysis pipeline to regenerate them — it costs the same as a full review, not a lightweight diff.
- **GitHub one-pending-review-per-PR pre-check**: before staging, the orchestrator checks for an existing self-authored PENDING review and refuses cleanly (rather than surfacing a raw 422) if one exists, directing the user to edit/submit or delete it in the web UI first.
- New Orchestrator Governance rule: "Draft mode never publishes" — explicitly forbids calling any submit/publish endpoint (GitHub review-events, GitLab `bulk_publish`) while staging.
- New structural tests in `tests/orchestration_contracts.bats` assert the draft OP never contains a live invocation of a publish/submit endpoint, and that `--draft`/`--publish`/`--read-back` are documented consistently across `SKILL.md`, `README.md`, `CLAUDE.md`, and `HELP.md`.

### Fixed

- **GitHub read-back's PENDING-review filter no longer uses an unresolved placeholder or invalid syntax.** Two bugs were found and fixed during live E2E and multi-agent review of this feature before release: an early version compared `.user.login` against a literal, never-resolved `"<self>"` string; a later fix for that introduced an invalid `gh api --jq --arg` invocation (`gh api`'s `--jq` flag takes exactly one query string and does not support jq's own `--arg`). Both made GitHub `--read-back` non-functional as written. Fixed by resolving the invoking user's login via `gh api user --jq .login` and piping the pending-review query to a standalone `jq --arg` call.
- **The GitHub pending-review pre-check no longer silently reports "0 pending reviews" when the login lookup fails.** A prior version fell back to an empty-string login on lookup failure and queried with it — an empty string can never match a real GitHub login, so the pre-check always returned a false "all clear" instead of genuinely skipping the check. It now skips the query entirely on lookup failure and warns explicitly.
- **GitLab read-back's net-new-finding staging no longer risks a stale-SHA race.** The diff-version SHAs used to position a new draft note were previously captured once at Phase 4b entry, before the full analysis pipeline reruns and the user confirms staging — an arbitrarily long window during which a new commit on the MR could make those SHAs stale. The SHAs are now re-fetched immediately before the staging call, and a failed re-fetch is reported as a distinct error rather than being misreported through the generic inline-post-failure path.
- **Four missing `--read-back` flag-conflict checks added**, closing gaps found across two independent review passes: `--read-back` combined with `--publish`/`--draft` previously produced a contradictory error-message loop (each error told the user to do the thing the other error forbade); `--read-back` combined with `--create-pr` on a branch with no existing PR/MR silently created a new PR and then ran the read-back against it, which by construction could have no prior draft.
- Corrected an overstated claim that GitHub's REST docs guarantee PENDING reviews are visible only to their author — the docs confirm the not-yet-submitted state but do not document an explicit access-control guarantee for who can see it beforehand. The docs and code comments now describe "unpublished" as the verified property and "author-only visible" as a reasonable but unverified assumption.
- Added a documented rollback path ("if draft mode misbehaves") for the (unlikely, but possible) case that a future GitHub or GitLab API change breaks the draft-staging invariant, plus a runtime notice appended to every successful draft-staging report reminding the user to confirm the review shows as Pending/draft in the web UI before sharing the PR link.
- Added a runtime migration notice printed when `--post-findings` is used without `--publish` or an explicit `--draft`, so a script or CI job that relied on the pre-1.13.0 immediate-publish default gets a live signal that behavior changed, not just a silent change in outcome.
- Fixed a pre-existing, unrelated bug in `run-phpcs.sh`: `$PHPCS_STANDARD` was only initialized on the live-`phpcs` code path, leaving it unbound (and the resulting `jq` call silently discarding findings) whenever the mock/offline path was used — including every run of the bats test suite. Now initialized unconditionally.

### Known limitations

- Bitbucket draft-review support is out of scope this release: the Cloud REST v2 comment schema has a `pending` field, but creating a pending comment via the public API is not confirmed in Atlassian's official documentation (the "Batched comments" feature is documented as UI-driven). Revisit with a live API spike.
- GitLab's draft-note staging and `--read-back` net-new-finding staging paths were not exercised against a live GitLab instance for this release — only GitHub was live-E2E-tested. Both are covered by structural bats tests asserting API-call shape, not by a live run. Treat the GitLab path as less battle-tested than GitHub's until a live GitLab E2E is performed.

## [1.12.2] - 2026-06-24

### Fixed

- **COMMENTS validation tightened; line 0 rejected** (#108): The inline review payload builder now rejects `LINE=0` values before constructing the `argjson` payload, preventing malformed GitHub API calls that would silently drop inline comments.
- **`LINE` validated before `argjson` construction** (#108): Added explicit numeric validation of the `LINE` variable before it is used in `--argjson` to prevent jq parse errors from propagating to the API call.
- **Prompt-injection guard centralized in `GOVERNANCE.md`** (#109): The canonical untrusted-input guard directive is now in `GOVERNANCE.md` (injected into every custom agent) rather than duplicated across individual agent prompts. Ensures new agents get the guard automatically.
- **jq-based JSON payload construction mandated in `PROVIDERS.md`** (#109): Documented requirement to use `jq --arg`/`--argjson` for all provider API payloads; string interpolation into JSON is prohibited.
- **SHA-pinned `ruby/setup-ruby` in `pages.yml`** (#110): The GitHub Pages CI action now pins `ruby/setup-ruby` to its full commit SHA rather than a floating tag, eliminating supply-chain risk on the docs build.

### Changed

- **AI review now runs on all PRs including renovate and dependabot** (#117): Removed the `github.actor != 'dependabot[bot]'` and `github.actor != 'renovate[bot]'` skip conditions from the dogfood workflow's `review` job. Every non-draft PR now receives a review. The `skip-ai-review` label remains as a per-PR escape hatch.
- **`review-gate` wrapper job removed from dogfood workflow** (#117): Branch protection on `main` now requires the `review` job directly. The gate wrapper was only needed to pass branch protection when bots were skipped; it is no longer necessary.
- **`fail-on-findings` wired into dogfood workflow** (#116): The dogfood `ai-pr-review.yml` passes `fail-on-findings: ${{ vars.AI_REVIEW_FAIL_ON_FINDINGS || 'false' }}` to the container action, enabling the CI automerge gate via the `AI_REVIEW_FAIL_ON_FINDINGS` repo variable.

### Internal

- **`plugin.json` version bump to `1.12.1`** (v1.12.1 release): Corrected inflated cost figures in `SKILL.md` ($30-80 replaced with measured ~$0.25 quick / ~$0.50-$1.25 full) and fixed token utilization table description in `README.md`.

---

## [1.12.0] - 2026-06-04

### Removed

- **`--diagrams` flag and Mermaid sequence diagram output** (#93): The opt-in `--diagrams` flag and the `## Sequence Diagrams` section in Block A have been removed. The feature was default-off and never produced reliable enough output to keep. A stale `--diagrams` flag passed by existing users is silently ignored. Removed from `SKILL.md`, `HELP.md`, `README.md`, `CLAUDE.md`, and `agents/pr-summarizer.md`.
- **`ai-pr-review` git submodule** (#89): Removed the stale `.gitmodules` entry and `.github/actions/ai-pr-review` submodule path left over from the earlier migration to the container action. No workflow logic changes.

### Fixed

- **Token utilization table: replaced unfillable In/Out/Cache columns with blended `Tokens` total** (#95): The Agent tool exposes only a single `subagent_tokens` combined total per agent — it does not provide an input/output/cache breakdown. The previous 8-column table had four permanently unfillable columns, causing inconsistent LLM output between runs. Replaced with a 5-column table (`Agent`, `Model`, `Tokens`, `Tools`, `Est. Cost`) using blended per-model rates (Opus ~$45/M, Sonnet ~$9/M, Haiku ~$0.8/M) with a `/cost` footnote for exact figures.
- **`shell.md` language profile: correct `suppressions.json` path** (#94): The path reference now correctly reads `skills/comprehensive-review/suppressions.json` instead of the vague `suppressions.json` (the file is not at the repo root).

---

## [1.11.0] - 2026-06-02

### Added

- **6 new static analyzers** (#86): Ported from `ai-pr-review` and wired into Phase 1b orchestration. All are opportunistic (silently skipped when the binary is absent) and use mock-file-based offline bats tests (no real binary invoked in CI).
  - **`run-eslint.sh`** — JavaScript/TypeScript linting via ESLint. Triggers on `.js`, `.jsx`, `.ts`, `.tsx`, `.mjs`, `.cjs` files; skips silently when no ESLint config is found in the repo root (`GITHUB_WORKSPACE`). Detects `--no-warn-ignored` support via `--help` (not `--version`, which short-circuits arg parsing). Severity mapping: `error` → High, `warning` → Medium.
  - **`run-hadolint.sh`** — Dockerfile linting. Triggers on `Dockerfile`, `Dockerfile.*`, and `*.dockerfile` variants. Severity mapping: `error` → High, `warning` → Medium, `info`/`style` → Low.
  - **`run-kube-linter.sh`** — Kubernetes manifest linting. Triggers on `.yaml`, `.yml`, and `.json` files that contain `apiVersion:` and `kind:` fields (content-sniff guard avoids running on non-K8s YAML). All findings mapped to Medium.
  - **`run-phpcs.sh`** — PHP CodeSniffer. Triggers on `.php` files. Uses `Drupal`/`DrupalPractice` standard when phpstan-drupal is available, falls back to `PSR12`. Remediation string uses the active standard (not hardcoded). Severity mapping: `error` → High, `warning` → Medium.
  - **`run-phpstan.sh`** — PHP static analysis. Triggers on `.php`, `.module`, `.inc`, `.install`, `.theme` files. Vendor paths (`phpstan-drupal`, `autoload.php`) resolved relative to `GITHUB_WORKSPACE` (repo root) rather than script CWD. All findings mapped to High.
  - **`run-tflint.sh`** — Terraform linting. Triggers on `.tf` and `.tfvars` files; runs per-directory, prepending the directory prefix to bare filenames in output. Captures exit code explicitly (`DIR_EC`) to distinguish violations-found (exit 1) from fatal config errors (exit >= 2). Severity mapping: `error` → High, `warning` → Medium, `notice` → Low.
- **96 new bats tests** (#86): Mock-file-driven test suites for all 6 new analyzers, covering no-op paths, schema conformance, severity mapping, stdin support, and tool-absent behavior. Total test suite grows from 54 to 150.

### Fixed

- **`checkov --compact` flag** (#87): Added `--compact` to the `checkov` invocation in `run-checkov.sh`. Without it, passing checks bloat the JSON output significantly, slowing processing and inflating context.
- **Trufflehog allowlist: single-quoted and unquoted YAML path entries no longer silently dropped** (#87): `_build_allowlist_json()` previously only extracted double-quoted path entries from `.trufflehog.yml`. Entries in YAML bare form (`- path/to/file`) or single-quoted form (`- 'path/to/file'`) were silently ignored, leaving findings at allowlisted paths unsuppressed. Awk state machine rewritten to handle all three forms. Block-termination patterns broadened from `/^[a-zA-Z]/` to `/^[^[:space:]]/` to correctly stop at top-level YAML keys starting with digits or underscores.

---

## [1.10.0] - 2026-05-29

### Added

- **`security-guidance` plugin integration via shared org-policy file** (#82): `security-reviewer` now reads the same `claude-security-guidance.md` org-policy file used by the `security-guidance@claude-plugins-official` plugin, giving both tools a single shared policy source. Phase 0 step 10 loads up to three locations in priority order (`~/.claude/`, `<repo>/.claude/`, `<repo>/.claude/claude-security-guidance.local.md`), concatenates with an 8 KB ceiling, and injects as a `SECURITY_POLICY:` directive into the security-reviewer task description. Policy rules are applied only to introduced or modified code. `security-guidance` is documented as a recommended companion plugin. The project-scoped paths are loaded from the reviewer's own checkout only — never from the branch under review in `--pr` mode — to prevent prompt injection via attacker-committed policy files.
- **`examples/claude-security-guidance.example.md`**: Annotated multi-section copy-and-fill-in template for org security policy rules, organized by category (data access, auth/secrets, injection/SSRF, dependencies, logging). The `.example.md` suffix is intentional — the loader matches the exact filename `claude-security-guidance.md`/`.local.md`, so the template is never auto-loaded.

### Fixed

- **`REPO_ROOT` undefined in policy loader**: The initial implementation referenced `${REPO_ROOT}` which was never assigned, causing the two repo-scoped policy file paths to silently expand to `/.claude/...` (filesystem root) and never load. Fixed by resolving `_sg_repo_root=$(git rev-parse --show-toplevel 2>/dev/null)` before the loop and using conditional expansion (`${VAR:+"$VAR/..."}`) to skip candidates when the variable is empty.
- **`HOME` unset in policy loader**: A hardened CI container or non-login Docker user with `HOME` unset would cause the user-wide candidate to expand to `/.claire/...`. Fixed by using `${HOME:+"$HOME/..."}` conditional expansion.
- **Truncation comment accuracy**: Updated comment to accurately describe that truncation is a hard character-offset cut that may split a mid-file rule (not a clean whole-rule drop), and added a `[SECURITY_POLICY truncated at 8KB limit]` marker so the agent and debugging users can see when content was cut.
- **Policy rules scoped to changed lines**: Added instruction to `security-reviewer.md` to apply policy rules only to introduced or modified code, not to pre-existing unchanged lines or occurrences in comments/string literals unless the rule explicitly targets them.

---

## [1.9.1] - 2026-05-28

### Removed

- **`/comprehensive-review-help` skill** (#81): Removed — the verbatim-output skill approach produces blank output in Claude Code. Users can access the full flag reference via `HELP.md` directly or via the README.

---

## [1.9.0] - 2026-05-27

### Added

- **Structured `category` field in `json-findings` contract** (#76): All custom agents (architecture-reviewer, security-reviewer, blind-hunter, edge-case-hunter, adversarial-general) and the CVE dependency check now emit a required `category` field with a fixed taxonomy (`authz`, `injection`, `dependency-cve`, `secret`, `architecture-coupling`, `test-gap`, `edge-case`, `observability`, `docs`, `lint`, `other`). Phase 2 normalization validates and normalizes the field. `SEVERITY.md` documents the full contract. This enables structured filtering and deduplication.
- **Gate evaluation extracted to `evaluate-gates.sh`** (#72): The four agent-dispatch gate checks (`GATE_ERROR_PATTERNS`, `GATE_CONTROL_FLOW`, `GATE_SECURITY_PATTERNS`, `GATE_CODE_OR_INFRA`) are now a standalone script at `skills/comprehensive-review/scripts/evaluate-gates.sh`. Inputs: `DIFF_FILE` and `DIFF_PATHS` env vars. Output: sourceable `key=value` pairs. Conservative fallback: all gates default to `true` when inputs are missing. Makes gate logic independently testable.
- **Auto-cheap routing for docs-only and low-risk-config diffs** (#78): When all changed files are documentation/meta (`DOCS_ONLY=true`), Opus agents are automatically skipped without requiring `--quick`, reducing cost by ~60%. When the diff contains only config/YAML/TOML with no security-sensitive patterns (`LOW_RISK_CONFIG=true`), specialist agents are skipped. Both modes still run pr-summarizer, code-reviewer, and triggered conditionals. Phase 5 reports the auto-cheap reason. `HELP.md` documents both modes.
- **Novelty pass for repeated low-value findings** (#77): After deduplication (new Phase 2f), Low and Medium findings whose `category+file` fingerprint appeared in ≥2 prior reviews in `PRIOR_REVIEW_CONTEXT` are annotated with `[recurring — appeared in prior reviews]`. Findings are never deleted or severity-demoted. Critical/High findings and `dependency-check` CVE findings are excluded. Requires `--no-mem` to disable; skipped when `--quick`, `--security-only`, or `--summary-only` mode is active, or when fewer than 2 prior review entries exist.
- **`/comprehensive-review-help` skill** (#73): Replaced the dead-end placeholder with a functional skill that outputs the full `HELP.md` content verbatim.
- **PR/MR body included in `PR_NARRATIVE`** (#70): All three providers (GitHub, GitLab, Bitbucket) now fetch the `body`/`description` field when collecting PR/MR metadata in `--pr <N>` mode. GitLab `description` and Bitbucket `description` are mapped to `body`. This reduces false positives by giving agents the author's intent statement.
- **`bats` test suite with 54 tests** (#74, #75): Added `tests/` directory with four test files:
  - `run_cve_check.bats` — 10 tests: `parse_go_mod` replace-directive ordering (covers #67 bug), no-op paths, and end-to-end OSV batch mock tests including CVSS v4 conservative fallback.
  - `run_trufflehog.bats` — 5 tests: verified/unverified secret demotions, empty mock, no changed files.
  - `evaluate_gates.bats` — 15 tests: all four gates with positive/negative cases and fallback behavior.
  - `orchestration_contracts.bats` — 24 golden tests: SKILL.md structural integrity, SEVERITY.md contract, PROVIDERS.md correctness, gate fixture decisions, and CVE category field.

### Fixed

- **Go `replace` directive ordering bug in CVE check** (#67): `parse_go_mod()` in `run-cve-check.sh` rewritten as two-pass awk using the `FNR == NR` idiom. The original single-pass code missed replace directives when `require` appeared before `replace` (the standard go.mod layout). Both orderings now resolve correctly; local-path replacements keep the original module.
- **`Write` tool missing from `allowed-tools` frontmatter** (#68): The `Write` tool is now listed in `SKILL.md`'s `allowed-tools` frontmatter, enabling `--output-file` functionality that was silently failing.
- **GitHub inline review incorrectly documented as using MCP tool** (#69): `SKILL.md` and `PROVIDERS.md` updated to reflect the actual `gh api repos/{owner}/{repo}/pulls/{pull_number}/reviews` invocation. `mcp__github-pat__create_pull_request_review` was never the implementation and is no longer referenced.
- **TruffleHog scanning wrong input** (#71): Phase 1b now pipes `$DIFF_PATHS` to `run-trufflehog.sh` instead of passing `$DIFF_FILE`. This lets TruffleHog scan live files at their real paths (for accurate detector matching and file:line attribution) rather than scanning a combined diff text blob.

### Changed

- **Secret redaction step renumbered** from 2f to 2g to accommodate the new novelty pass (2f).
- **Step 2e deduplication** now uses the structured `category` field for file-level deduplication, not the informal bracketed prose label.
- **PROVIDERS.md**: GitHub inline review section rewritten to show actual `gh api` invocation; `body` field documented for all three providers' metadata fetch commands.
- **SEVERITY.md**: New "json-findings field contract" section with the full field table and category taxonomy.

---

## [1.8.11] - 2026-05-27

### Added

- New `GOVERNANCE.md` directive: **Cite evidence in the finding.** Findings must reference the specific code that exhibits the problem (snippet, symbol, or pattern at `file:line`) — the json-findings location fields are not the citation. Intended to reduce hallucinated structural findings; effectiveness has not been measured.
- New `GOVERNANCE.md` directive: **Refuse incoherent input.** If a diff contradicts its own commit message or claims to fix something it doesn't touch, agents surface that as a top-level finding rather than reviewing line-by-line as if coherent.
- New Orchestrator Governance directive in `SKILL.md`: **Cite the observed result, not the action taken.** Phase 4/4b/5 success claims reference the provider-returned URL, ID, or status — not just the fact that an API call was attempted.
- Phase 4/4b/5 capture-variable wiring to back the new directive with mechanism rather than text. Phase 4 PR/MR creation captures provider stdout/exit into `CREATED_PR_URL`/`CREATED_PR_ERROR`; Phase 4 comment posting captures `POSTED_COMMENT_REF`/`POSTED_COMMENT_ERROR`; Phase 4b inline review posting captures `POSTED_REVIEW_URL`/`POSTED_REVIEW_ID`/`INLINE_POSTED_COUNT`/`INLINE_FAILED_COUNT`/`POSTED_REVIEW_ERROR`; Phase 5 worktree cleanup verifies removal via `[[ -e "$WORKTREE_PATH" ]]` and sets `WORKTREE_REMOVED`; Phase 5 claude-mem POST captures `MEM_HTTP_STATUS` via `curl -w '%{http_code}'` and only reports success on 2xx. Phase 5 terminal output cites these captured values rather than asserting success from the fact that an API call was invoked. Failure paths are reported plainly when capture variables are empty.
- BLIND_HUNTER_NOTE extended to scope the new "Refuse incoherent input" directive to incoherence visible within the diff itself (e.g., a hunk that calls a symbol the same diff just deleted), preserving blind-hunter's zero-context constraint.

### Fixed

Robustness fixes to the Phase 4/4b/5 capture-variable patterns, addressing AI review findings on PR #79:

- **`gh pr create` URL extraction:** initial fix replaced combined-stream `grep` with a two-step `gh pr create` (for exit code) → `gh pr view --json url --jq '.url'` pattern. Round-2 review correctly noted that `gh pr view` without an explicit branch argument can return the wrong PR if HEAD is detached. Final form: capture stdout into `CREATE_OUT` and stderr into a temp file separately (`gh pr create ... 2>"$CREATE_ERR_FILE"`), then extract the URL from stdout with a PR-path-specific regex `https://[^[:space:]]+/pull/[0-9]+`. `gh pr create` writes exactly the new PR URL to stdout on success, so this is unambiguous. Same separated-stream pattern applied to `glab mr create`, extracting against `merge_requests/[0-9]+`.
- **`POSTED_COMMENT_REF` empty-on-success false-failure:** exit code is now the primary success signal for `gh pr comment` / `glab mr comment`. An empty URL on RC=0 is reported as `(posted; URL not reported by gh)` rather than treated as failure — preventing a false failure report and a duplicate comment on retry.
- **`INLINE_POSTED_COUNT` parsed via follow-up GET, not from POST response:** GitHub silently drops inline comments whose target line is outside the diff (despite the Phase 4b step 1 valid-line filter — GitHub's own validation is stricter for renamed files, large hunks, etc.). The POST `/pulls/{N}/reviews` response does not include a `.comments` array — only the GET `/pulls/{N}/reviews/{review_id}/comments` endpoint does. After a successful POST, a follow-up GET retrieves the actual posted-comment count. A delta vs the request length triggers a "GitHub accepted the review but dropped <N> inline comment(s)" warning. (An earlier attempt parsed `(.comments // []) | length` of the POST response — which always evaluated to 0 because that field doesn't exist on POST. Fixed in the same PR before merge.)
- **GitLab inline-warning placeholder:** the warning log now uses `printf` with `${THREAD_RESPONSE:-no thread ID returned}` instead of a literal `<error or ...>` placeholder, so warnings carry the actual response content.
- **`git worktree remove` stderr capture:** previously used `2>/dev/null || true` and then synthesized `WORKTREE_CLEANUP_ERROR="path still exists at ..."` which never carried the actual git error. Now captures stderr into `WORKTREE_REMOVE_ERR` before the path-existence check; `WORKTREE_CLEANUP_ERROR` falls back to the captured stderr.
- **`MEM_RESPONSE_FILE` mktemp guard + response body preserved:** `mktemp` now falls back to `/dev/null` on failure (preventing curl from writing to an empty-string path). The response body is read into `MEM_RESPONSE_BODY` before the file is deleted, so server error bodies survive for diagnostics when `MEM_SAVED=false`. Documented tradeoff: when mktemp falls back to `/dev/null`, the response body is unrecoverable — `MEM_RESPONSE_BODY` stays empty even on server-side failures. The HTTP status code is still captured via `curl -w '%{http_code}'`, so `MEM_SAVED` still works correctly; only the diagnostic body is lost. This is rare (mktemp /tmp failure is a system-level problem) and not worth a more elaborate fallback.

### Changed

- Aligned plugin governance with refactored `~/.claude/CLAUDE.md` (Outcome Verification, Disagreement & Alternatives sections). Items deemed out of scope for a per-run review tool (Session Self-Audit, Active Guardrails, Checkpoint Triggers list, Pre-Claim/Pre-Action Check) were intentionally not imported.
- Updated `CLAUDE.md` Governance directives summary to enumerate the two new agent-side directives under the Honesty bullet and to reflect the extended BLIND_HUNTER_NOTE scope.

---

## [1.8.10] - 2026-05-27

### Changed

- Removed all `--help` / `-h` flag handling from `SKILL.md`. Every implementation approach tried in v1.8.1–v1.8.9 proved unreliable (see note below). `HELP.md` remains as reference documentation accessible in the repo and README.
- Replaced a competitor-specific descriptor with neutral language across `SKILL.md`, `HELP.md`, `README.md`, `plugin.json`, and `CLAUDE.md`.

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
