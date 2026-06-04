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

**Orchestrator model matters most.** Run this skill on **Sonnet** for ~5× lower orchestrator cost. Opus is reserved for the internally-spawned `architecture-reviewer` and `security-reviewer` agents.

| Orchestrator model | Typical cost (medium PR, ~1,700 lines, full run) |
|--------------------|------------------------------------------------:|
| Opus 4.8 | **$60–80** |
| Sonnet 4.6 (recommended) | **$30–45** |

**Cost drivers:**
- ~80% of cost comes from the two Opus specialist agents and the orchestrator itself when run on Opus
- The orchestrator accumulates ~100k+ cached tokens over 100+ tool-call turns; at Opus cache-read rates ($1.50/M) this alone costs ~$15–30 per review
- At Sonnet cache-read rates ($0.30/M) the same context costs ~$3–6

## Cost-saving options

**`--quick` mode:** Skips architecture-reviewer, security-reviewer, blind-hunter, edge-case-hunter, comment-analyzer, and type-design-analyzer. Roughly 60–80% cheaper vs. full run. Example measurement: ~79K agent tokens for `--quick` vs ~317K for a full run on a documentation PR.

**`--depth normal` (default):** Opus reserved for 2 agents. `--depth deep` promotes 2 more to Opus and roughly doubles cost.

**`--output-file <path>`:** Writes the report to disk during the review session, avoiding a follow-up request that pays Opus rates against a large accumulated context. Saves ~$5–15 on large PRs.

**Auto-cheap routing:** TIER=tiny, DOCS_ONLY, and LOW_RISK_CONFIG activate automatically — no flags needed. See [Usage & Flags](usage#auto-cheap-routing) for details.

## Per-agent optimizations

**Pre-flight context sharing:** The orchestrator reads `CLAUDE.md` and the commit log once in Phase 0 and passes condensed versions to agents, eliminating redundant reads.

**Per-file diff digest:** The orchestrator pre-computes a compact per-file summary (stat line + first changed hunk, ≤20 lines per file, capped at 200 total lines) and passes it to Opus agents upfront. This allows them to prioritize which files to investigate deeply without burning tool calls on discovery.

**Opus agent tool-call budget:** `architecture-reviewer` and `security-reviewer` are instructed to prefer parallel batched reads and stop at 25 tool calls. Phase 5 reports actual tool-call counts with a warning if the budget is exceeded.

**blind-hunter cost:** Particularly cheap — it receives only the raw diff or plain file list, with no project context at all.

**Agent scope boundaries:** Explicit boundaries prevent duplicate analysis across agents, eliminating redundant LLM calls for the same concerns.

## Token utilization table

Phase 5 always prints a per-agent breakdown of input/output/cache tokens and estimated USD cost, so you can see where budget is going without running `/cost`:

| Column | Description |
|--------|-------------|
| Agent | Agent name |
| Model | Resolved model (e.g., "Sonnet 4.6") |
| Input | Input tokens consumed |
| Output | Output tokens generated |
| Cache Read | Tokens read from prompt cache (when active) |
| Total | Combined token count |
| Est. Cost | Estimated cost at public list prices |

Costs use public list prices and do not reflect enterprise discounts.
