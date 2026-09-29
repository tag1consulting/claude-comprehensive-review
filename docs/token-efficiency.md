---
layout: default
title: Token Efficiency
nav_order: 6
render_with_liquid: false
---

# Token Efficiency

The skill uses a tiered context-passing strategy to minimize token consumption across a fleet of agents.

## Tiered context passing

| Diff size | Strategy |
|-----------|---------|
| **TIER=tiny** (<50 lines AND ≤3 files) | All agents receive the full diff inline; several agents are skipped entirely; pr-summarizer runs on Haiku. Estimated floor: ~$0.30. |
| **Small** (<300 lines) | Full diff passed inline to all agents — tool-call overhead for selective reads exceeds the cost of the full diff at this size. |
| **Medium/large** (300+ lines) | Custom agents receive a structured **file manifest** (file list, categories, languages, line counts) and use selective `git diff <base>...HEAD -- <file>` reads. Toolkit agents receive only the diff slices relevant to their specialty. Lockfiles, vendor dirs, and checksum files are excluded from the manifest. |

## Cost expectations

Run this skill on **Sonnet** — the orchestrator does structured workflow coordination, not deep reasoning. Opus is reserved for the internally-spawned `architecture-reviewer` and `security-reviewer` agents.

| Mode | Typical cost |
|------|------------:|
| `--quick` | **~$0.25** |
| Full run (Sonnet orchestrator) | **~$0.50–$1.25** |

## Cost-saving options

**`--quick` mode:** Skips architecture-reviewer, security-reviewer, blind-hunter, edge-case-hunter, comment-analyzer, and type-design-analyzer. Roughly 60–80% cheaper vs. full run. Example measurement: ~79K agent tokens for `--quick` vs ~317K for a full run on a documentation PR.

**`--depth normal` (default):** Opus reserved for 2 agents. `--depth deep` promotes 2 more to Opus and roughly doubles cost.

**`--output-file <path>`:** Writes the report to disk during the review session, avoiding a separate follow-up request against a large accumulated context.

**Auto-cheap routing:** TIER=tiny, DOCS_ONLY, and LOW_RISK_CONFIG activate automatically — no flags needed. See [Usage & Flags](usage#auto-cheap-routing) for details.

## Per-agent optimizations

**Pre-flight context sharing:** The orchestrator reads `CLAUDE.md` and the commit log once in Phase 0 and passes condensed versions to agents, eliminating redundant reads.

**Per-file diff digest:** The orchestrator pre-computes a compact per-file summary (stat line + first changed hunk, ≤20 lines per file, capped at 200 total lines) and passes it to Opus agents upfront. This allows them to prioritize which files to investigate deeply without burning tool calls on discovery.

**Opus agent tool-call budget:** `architecture-reviewer` and `security-reviewer` are instructed to prefer parallel batched reads and stop at 25 tool calls. Phase 5 reports actual tool-call counts with a warning if the budget is exceeded.

**blind-hunter cost:** Particularly cheap — it receives only the raw diff or plain file list, with no project context at all.

**Agent scope boundaries:** Explicit boundaries prevent duplicate analysis across agents, eliminating redundant LLM calls for the same concerns.

## Token utilization table

Phase 5 always prints a per-agent breakdown of tokens, tool calls, and estimated USD cost, so you can see where budget is going without running `/cost`:

| Column | Description |
|--------|-------------|
| Agent | Agent name |
| Model | Resolved model (e.g., "Sonnet", "Opus", "Haiku") |
| Tokens | Combined token count (`subagent_tokens`). Measured against subagent transcripts, this is the agent's final-turn context size (mostly cache reads), not cumulative usage. The Agent tool returns no input/output/cache breakdown |
| Tools | Number of tool calls the agent made |
| Est. Cost | Estimated cost from a blended per-model rate (Opus ~$8/M tokens, Sonnet ~$4/M, Haiku ~$2/M) |

Costs are blended-rate estimates, not public list prices. Because the token total is a final-turn context size that is mostly cheap cache reads, the blended rates are much lower than list price per token. They were calibrated from about 40 measured subagent transcripts at Opus 5.5 / Sonnet 5.5 / Haiku 4.5 list prices. Per-agent cost measured 2.7–4.5 $/M for Sonnet and 5.8–8.7 $/M for Opus, so treat each figure as roughly ±40%. The Haiku rate rests on a single sample. Run `/cost` for exact figures.

### Keeping the rates current

`skills/comprehensive-review/model-pricing.json` holds the blended rates and a snapshot of Anthropic's published per-model prices. A weekly GitHub Actions workflow (`model-pricing-check.yml`) runs `scripts/check-model-pricing.sh`, which compares the published pricing table with the snapshot and files an issue labeled `pricing-drift` when a model is added, removed, or repriced (or when the page can no longer be parsed). To resolve one: run `scripts/check-model-pricing.sh --update`, recalibrate the blended rates against measured transcripts if the list prices changed, and update the rates in `SKILL.md` Phase 5 and this page. `tests/model_pricing.bats` fails if those three places disagree.
