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

Combined: ~640 additions across varied languages (markdown, shell, YAML fragments), fix/feature/refactor mix, both small and large diffs represented.

### Per-PR procedure

For each sample PR:

1. Fetch the PR's metadata (base, head) via `gh pr view <N> --json baseRefName,headRefName,commits`
2. Check out the head commit in a temp worktree
3. Build the exact same context the `comprehensive-review` skill would build in Phase 1 for `code-reviewer`: the full diff against the base (small-diff path for all our samples)
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
- If flip: a follow-up PR that edits `SKILL.md:255,270` and the `README.md` roster table.

## Option 2 design notes (for a future `--experiment-model` flag)

Preserved here so the one-shot experiment can be upgraded to a permanent A/B capability later without rediscovering the design.

### Motivation

Every future model decision (code-reviewer Opus/Sonnet, what model architecture-reviewer should run on when Opus 5 ships, whether blind-hunter benefits from Haiku, etc.) requires the same comparison pattern. A flag would let anyone run that comparison on their own PRs without having to write a new methodology doc each time.

### Proposed shape

```
/comprehensive-review --experiment-model <agent>=<model>[,<agent>=<model>...]
```

Example: `/comprehensive-review --experiment-model code-reviewer=opus,blind-hunter=haiku`

### Orchestrator changes

In `skills/comprehensive-review/SKILL.md`:

1. **Phase 0 flag parsing** — extract `--experiment-model` into a map `EXPERIMENT_MODELS: {agent_name: override_model}`. Validate: each agent name exists in the agent roster; each model is one of `opus`, `sonnet`, `haiku`. Invalid input → error and stop.
2. **Phase 1 agent spawn sites** — at every agent spawn call (currently lines 268, 270, 274, 276, 278, 282, 292, 293, 297, 298, 299), the `model:` parameter becomes `EXPERIMENT_MODELS.get(agent_name, <default_model>)`. The defaults stay exactly as they are today; the flag is pure override.
3. **Dual-run mode** — `--experiment-model <agent>=<model>:compare` runs the named agent twice (default + override) and emits both outputs side-by-side in Block B under a "Model Comparison" heading. The rest of the review runs normally with defaults.
4. **Block B annotation** — when any override is active, Block B header gets a line: "Experiment mode: code-reviewer=opus (default: sonnet)". Posted reviews include the same annotation so readers know the output is not from the skill's default configuration.
5. **Quick-mode interaction** — `--experiment-model` is allowed with `--quick`, but only applies to agents that `--quick` would have run anyway. Overrides on skipped agents are ignored with a warning.
6. **`--no-post` default** — when `--experiment-model` is passed, default to `--no-post` unless the user also passes `--post-summary` or `--post-findings`. Experiments shouldn't write to other people's PRs by accident.

### Edge cases to handle

- The override model is the same as the default (no-op — warn but don't error)
- Multiple overrides for the same agent (last-wins, or error — pick one, document it)
- Override targets an agent that's conditional and doesn't get triggered (no-op — warn)
- Override targets a subagent that doesn't exist (error and stop at Phase 0)

### Not-in-scope for Option 2

- Automated grading / accuracy measurement — still a human task
- Persistent history of experiment results — if wanted, layer on top via claude-mem
- Model parameters other than the model name (temperature, max_tokens, etc.) — not exposed by the Agent tool

### Open design questions

- Should `--experiment-model` force token-consumption reporting to always be visible in Block B, to make cost comparisons easy? Currently token usage is not reported at all.
- Should `:compare` be a separate flag (`--experiment-compare`) or a suffix on `--experiment-model`? Suffix is terser; separate flag is more discoverable via `--help`.

### Implementation cost estimate

~30–50 lines of SKILL.md changes (flag parse, per-spawn-site lookup, Block B annotation, `:compare` branch). No agent-file changes required — overrides are purely orchestrator-side. No `README.md` changes beyond the flags table.

## Timeline and status

- **2026-04-16** — Methodology and Option 2 design captured (this commit).
- **TBD** — Experiment run and results posted to [#24](https://github.com/tag1consulting/claude-comprehensive-review/issues/24).
- **TBD** — Follow-up PR to flip the assignment, if the data supports it.
