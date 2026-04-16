# Experiment: code-reviewer on Opus vs. Sonnet

Tracks the evaluation described in [issue #24](https://github.com/tag1consulting/claude-comprehensive-review/issues/24). This document is the methodology and design notes. Raw per-PR comparison outputs live outside the repo (in a session-local `claude/` directory); only the summary recommendation lands on the issue.

## Question

Should the `code-reviewer` agent run on Opus instead of Sonnet?

`code-reviewer` is the only always-run agent that reports bugs — it runs in every mode, including `--quick` where the other review agents are skipped. If Sonnet misses real bugs Opus would catch, `--quick` users have no backstop. Current assignment in `skills/comprehensive-review/SKILL.md:255,270` is `sonnet`.

## Methodology

The evaluation uses a Claude-driven runner (Option 2 from the PR discussion): a Claude Code session iterates over a fixed sample of PRs and, for each one, spawns the `code-reviewer` subagent twice — once with `model: sonnet`, once with `model: opus` — with identical context otherwise. Outputs are saved side-by-side for human grading.

This is **not** a shell-script harness. There is no CLI entry point to invoke a Claude Code subagent from outside a Claude session, so the "runner" is the orchestrator Claude acting as the driver. See the [Option 2 design notes](#option-2-design-notes-for-a-future---experiment-model-flag) below for what a permanent, flag-based version would look like.

### Sample set

Six PRs from this repo's history, chosen to span change sizes and types. This repo was chosen because we have full context to grade findings against the actual outcomes (what shipped, what broke, what got fixed in follow-ups).

| PR | Type | Additions/Deletions | Why chosen |
|----|------|---------------------|------------|
| #14 | fix | +15 / -5 | Small, targeted bug fix — tests baseline behavior on low-complexity code |
| #16 | feature | +223 / -86 | Large multi-provider feature — stresses cross-file reasoning |
| #17 | feature | +102 / -1 | Medium integration (claude-mem) — boundary/error-handling heavy |
| #18 | fix | +6 / -12 | Small security/UX fix (write-op confirmation) — high signal-to-noise ratio |
| #21 | fix | +26 / -26 | Medium pure-refactor (subagent_type labels) — style and consistency focus |
| #12 | refactor | +267 / -550 | Large token-optimization refactor — delete-heavy, tests regression-spotting |

Combined: ~640 additions across markdown and shell, fix/feature/refactor mix, both small and large diffs represented. This repo has no production code surface — the samples stress prose-accuracy and consistency-checking more than line-level bug spotting. If the experiment's signal is weak, a second round using a codebase with more typical bug density may be warranted.

### Per-PR procedure

For each sample PR:

1. Fetch the PR's metadata (base, head) via `gh pr view <N> --json baseRefName,headRefName,commits`
2. Check out the head commit in a temp worktree
3. Build the exact same context the `comprehensive-review` skill would build in Phase 1 for `code-reviewer`: the full diff against the base. (`code-reviewer` always receives the full diff regardless of diff size — SKILL.md Phase 1 line 270 — so no size-tiering matters for this agent.)
4. Spawn `code-reviewer` twice:
   - Call A: `subagent_type: "pr-review-toolkit:code-reviewer"`, `model: "sonnet"`
   - Call B: `subagent_type: "pr-review-toolkit:code-reviewer"`, `model: "opus"`
   - Both calls receive the identical prompt — only the model differs
5. Save both outputs to `claude/experiment-issue-24/results/pr-<N>-sonnet.md` and `...-opus.md`
6. Record token usage per call (from the Agent tool's usage report)

After all six PRs are processed, produce a comparison table and write-up.

### Grading rubric

For each finding reported by either model, classify as:

- **TP (true positive)** — a real issue that would have warranted a change. Use knowledge of subsequent commits / linked issues / review comments to verify.
- **FP (false positive)** — flagged something that is not actually a problem in context
- **Style-only** — a real stylistic preference but not a bug and not a convention violation

Per-PR metrics:
- TPs caught by Opus only (false negatives of Sonnet)
- TPs caught by Sonnet only (false negatives of Opus)
- TPs caught by both
- FP rate per model
- Token consumption per model

### Decision criteria

Flip to Opus if **either**:
- Sonnet has a false-negative rate of >1 TP per ~5 PRs (i.e., at least 2 missed real bugs across the 6-PR sample), **or**
- Opus produces a materially lower FP rate (reducing reviewer fatigue is a legitimate reason to pay more)

Stay on Sonnet if:
- Both models produce substantially overlapping findings on real bugs
- Opus's "wins" are style-only or marginal

### Deliverable

A comment on issue #24 with:
- The comparison table (per-PR TP/FP counts for each model)
- Summary token cost per model across the 6-PR run
- Recommendation: flip, stay, or run a larger sample
- If flip: a follow-up PR that edits both `code-reviewer` model assignments in `SKILL.md` Phase 1 (the "Model assignments" table and the inline entry under "Always-run agents") and the `README.md` agent roster table. (Note: PR #23 corrected the `README.md` roster to read "Sonnet" as part of the pre-existing drift fix. If PR #23 is abandoned, the README edit is needed regardless of experiment outcome.)

## Option 2 design notes (for a future `--experiment-model` flag)

Preserved here so the one-shot experiment can be upgraded to a permanent A/B capability later without rediscovering the design.

### Motivation

Every future model decision (code-reviewer Opus/Sonnet, what model architecture-reviewer should run on when Opus 5 ships, whether blind-hunter benefits from Haiku, etc.) requires the same comparison pattern. A flag would let anyone run that comparison on their own PRs without having to write a new methodology doc each time.

### Proposed shape (revised after architectural review)

```
/comprehensive-review --experiment-model <agent>=<model>[,<agent>=<model>...]
```

Example: `/comprehensive-review --experiment-model code-reviewer=opus,blind-hunter=haiku`

**Pure override only.** No `:compare` mode — see "Dropped from scope" below for why.

### Orchestrator changes

In `skills/comprehensive-review/SKILL.md`:

1. **Canonical agent-name registry** (new, Phase 1 preamble) — add a single source-of-truth mapping of short user-facing names → `subagent_type` strings + default models. Example: `code-reviewer` → (`pr-review-toolkit:code-reviewer`, sonnet). The flag accepts short names; the registry handles the namespace translation. Also used to anchor validation in step 2 and keep the README roster table honest.

2. **Phase 0 flag parsing** — extract `--experiment-model` into a map `EXPERIMENT_MODELS: {short_name: override_model}`. Validate: each short name exists in the registry. **Do not** restrict model values to `{opus, sonnet, haiku}` — accept any non-empty token so pinned IDs (`claude-opus-4-7`) and future aliases work. Let the Agent tool reject invalid model strings at spawn time. Invalid short names → error and stop.

3. **Phase 1 agent spawn sites** — at every agent spawn in the "Agent Roster" section, replace hardcoded `model:` values with `EXPERIMENT_MODELS.get(short_name, registry_default)`. Defaults are sourced from the registry, not hardcoded per spawn site (removes a maintenance footgun). Reference spawn sites by section heading in this doc rather than line numbers (they rot).

4. **Block B annotation** — when any override is active, Block B gets a header line listing all active overrides: "Experiment mode: code-reviewer=opus (default: sonnet), blind-hunter=haiku (default: sonnet)". Posted reviews include the same annotation.

5. **Interaction with scope-limiting modes** — define one generalized rule: if an override targets an agent that will not run in the active mode (any of `--quick`, `--security-only`, `--summary-only`, or a triggered-conditional agent that was not triggered), warn and continue. The warning names the agent and the reason.

6. **Interaction with posting flags** — when any override is active, require an explicit opt-in flag (e.g., `--experiment-post`) to post any output to a PR/MR. Without that flag: `--post-summary`, `--post-findings`, and `--pr <N>` all behave as `--no-post`. Rationale: experiment output is not the standard review, and posting it to someone else's PR is a credibility hazard.

7. **Interaction with claude-mem** — when any override is active, skip the `POST /api/memory/save` call at Phase 5 entirely. Experiment runs must not contaminate the historical review corpus that `architecture-reviewer` and `security-reviewer` see in Phase 0 step 5b. Retrieval (read path) is unaffected; only writes are suppressed.

### Edge cases to handle

- Override model equals default (no-op — warn but don't error)
- Multiple overrides for the same agent (error at Phase 0 — last-wins is surprising for a debugging feature)
- Override targets an agent skipped by mode or trigger (warn, continue — see step 5)
- Override targets an unknown short name (error, stop at Phase 0)
- `--experiment-model` combined with `--pr <N>` (allowed, but step 6 suppresses posting unless `--experiment-post`)

### Dropped from scope (reconsidered after architectural review)

- **`:compare` mode.** Running an agent twice and rendering both outputs breaks the Block B `file:line` dedup contract (findings from run A and run B with the same location would collapse). Fixing that means either a special-case path that bypasses normalization or a separate Block C — either materially enlarges the feature. The methodology section above already solves the comparison use case as a one-shot Claude-driven procedure, so a permanent flag for it is not justified. If comparison is needed later as a persistent feature, design it as a separate `--experiment-compare` flag with its own output block and its own dedup rules, not as a suffix on `--experiment-model`.

### Not-in-scope for Option 2

- Automated grading / accuracy measurement — still a human task.
- Persistent history of experiment results — tagging-and-filtering in claude-mem is possible but out of scope.
- Model parameters other than the model name (temperature, max_tokens, etc.) — not exposed by the Agent tool.

### Open design questions

- Should `--experiment-model` force token-consumption reporting to always be visible in Block B, to make cost comparisons easy? Currently token usage is not reported at all.
- Should the registry live in SKILL.md (current proposal) or in a separate structured file that `plugin.json` could also reference? A structured file is more extensible but moves from one source of truth to one source + one loader.

### Implementation cost estimate (revised)

Realistic scope is wider than initially estimated:

- SKILL.md: ~100–150 lines across Phase 0 flag parse, Phase 1 registry + spawn-site rewrites, Phase 4/4b posting-flag suppression, Phase 5 claude-mem skip, generalized warning rule for scope-limiting modes, conflict-check updates. Plus the registry table itself.
- README.md: flag added to the flags table; agent roster table's Model column needs a "(default)" qualifier or footnote.
- HELP.md: full entry for the new flag + `--experiment-post`.
- CLAUDE.md: note in the editing guidelines that agent name/model changes must also update the registry.

No agent-file changes required — overrides remain purely orchestrator-side, which preserves blind-hunter's zero-context constraint.

## Timeline and status

- **2026-04-16** — Methodology and Option 2 design captured (this commit).
- **TBD** — Experiment run and results posted to [#24](https://github.com/tag1consulting/claude-comprehensive-review/issues/24).
- **TBD** — Follow-up PR to flip the assignment, if the data supports it.
