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
| Tokens | Combined token count (`subagent_tokens`) — the Agent tool returns only a single total per agent, with no input/output/cache breakdown |
| Tools | Number of tool calls the agent made |
| Est. Cost | Estimated cost from a blended per-model rate (Opus ~$45/M tokens, Sonnet ~$9/M, Haiku ~$0.8/M) |

Costs are blended-rate estimates, not public list prices — the underlying token total doesn't distinguish input from output from cache reads, so an exact list-price calculation isn't possible from what the Agent tool returns. Run `/cost` for exact figures.
