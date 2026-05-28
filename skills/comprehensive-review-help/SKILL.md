---
name: comprehensive-review-help
description: "Display usage reference for the /comprehensive-review skill: flags, modes, agent tiers, and examples."
---

Display the following help text verbatim. Do not interpret or modify it. Output it directly to the terminal, then stop.

---

/comprehensive-review — Comprehensive PR/MR Review

Run a comprehensive PR/MR review using specialized agents.
Supports GitHub (including Enterprise), GitLab, and Bitbucket.

Model tip: run this skill on Sonnet (not Opus) — the orchestrator does structured
workflow coordination, not deep reasoning. Opus is reserved for the specialist agents
(architecture-reviewer, security-reviewer) that are spawned internally. Running on
Opus costs ~$60–80 for a medium PR; Sonnet costs ~$30–45. Use --quick for ~60–80%
cheaper reviews that skip the two Opus agents entirely.

Tiny-PR tip: when the diff is under 50 lines and ≤3 files, the skill automatically
selects TIER=tiny — pr-summarizer drops to Haiku, and Opus agents are skipped unless
infra/security-path triggers promote them back. No flag needed; estimated floor cost
drops from ~$1 to ~$0.30.

Usage
  /comprehensive-review [flags]

Flags
  --base <branch>    Compare against a different base branch (default: auto-detect or main)
  --quick            Fast mode: pr-summarizer + code-reviewer + triggered error/test agents.
                     Skips security, architecture, blind-hunter, edge-case-hunter, comment,
                     and type analysis. Roughly 60–80% cheaper depending on diff composition.
  --diagrams         Include Mermaid sequence diagrams in the summary (default: omitted;
                     always omitted in --quick)
  --security-only    Run security-reviewer + CVE check (on changed dep manifests) only
  --summary-only     Run pr-summarizer only

  --create-pr        Create a PR using the summary (Block A) as the description
  --post-summary     Post summary (Block A) as a comment on an existing PR/MR
  --post-findings    Post findings (Block B) as inline review on an existing own PR/MR
  --no-findings      Suppress posting findings (useful for dry-run with --pr)
  --no-post / --local  Explicit alias for the default: skip all remote operations
  --pr <number>      Review an existing PR/MR by number (external review mode)
  --depth <tier>     Agent depth: normal (default) or deep.
                     deep: blind-hunter and edge-case-hunter run on Opus,
                     Opus agents use extended step-by-step reasoning, and a
                     CVE reachability triage pass annotates which vulns are
                     actually reachable in the diff.
  --provider <name>  Override git provider detection (github, gitlab, bitbucket)
  --no-enrich-context  Disable symbol context enrichment (on by default for all
                     full runs except TIER=tiny)
  --no-mem           Disable claude-mem integration (auto-detected when available)
  --no-suppress      Disable all suppression rules (shows every finding)
  --min-confidence N Filter findings below confidence N (0–100; default 75)
  --output-file <p>  Write Block A + Block B to a markdown file at path <p>

Default behavior
  All runs:          Everything local. No remote posting unless explicitly requested.
  No PR exists:      Use --create-pr to create one.
  Existing own PR:   Use --post-summary/--post-findings to post.
  --pr <N>:          Local only. Use --post-findings to post an inline review.

Agents — full run
  Always:            pr-summarizer, code-reviewer
  Full-run-only:     architecture-reviewer, security-reviewer, blind-hunter, edge-case-hunter,
                     issue-linker (GitHub only)
  Conditional:       silent-failure-hunter, pr-test-analyzer, comment-analyzer, type-design-analyzer

Agents — --quick mode
  Always:            pr-summarizer (no diagrams), code-reviewer
  Conditional:       silent-failure-hunter, pr-test-analyzer (if patterns match)
  Skipped:           all full-run-only + comment-analyzer, type-design-analyzer, issue-linker

Deterministic checks (all modes except --summary-only)
  dependency-check:  Queries OSV.dev for CVEs in changed dependency manifests.
                     Triggers on: go.mod, package.json, requirements*.txt, composer.json.

Examples
  /comprehensive-review                         Review current branch, everything local
  /comprehensive-review --create-pr             Review and create PR with summary
  /comprehensive-review --quick                 Fast review, skip expensive agents
  /comprehensive-review --post-findings         Post findings on existing own PR
  /comprehensive-review --pr 42                 Review PR #42 locally
  /comprehensive-review --pr 42 --post-findings Review PR #42 and post inline findings

Provider support
  Detected automatically from git remote URL. Override with --provider.
  GitHub / GitHub Enterprise:  Full support (gh CLI required)
  GitLab:                      Full support (glab CLI required)
  Bitbucket:                   PR creation, summary, comment posting.
                               Inline review comments not supported.

Full documentation: skills/comprehensive-review/HELP.md (after plugin install)
