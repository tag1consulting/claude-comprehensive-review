/comprehensive-review — Comprehensive PR/MR Review

Run a full CodeRabbit-style review using specialized agents.
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
  --no-post / --local  Skip all remote operations and issue-linker, display everything locally
  --pr <number>      Review an existing PR/MR by number (external review mode;
                     use --pr for all providers, including GitLab MRs)
  --depth <tier>     Agent depth: normal (default) or deep.
                     deep: blind-hunter and edge-case-hunter run on Opus,
                     Opus agents use extended step-by-step reasoning, and a
                     CVE reachability triage pass annotates which vulns are
                     actually reachable in the diff.
  --provider <name>  Override git provider detection (github, gitlab, bitbucket)
  --no-mem           Disable claude-mem integration (auto-detected when available)
  --output-file <p>  Write Block A + Block B to a markdown file at path <p> during Phase 5.
                     Use this to avoid re-running the review in a fresh session just to save
                     the output — saves ~$5–15 on large PRs where the post-review context
                     would otherwise force a new expensive session.

  --help             Show this help

Default behavior
  No PR exists:      Everything local. Use --create-pr to create one.
  Existing own PR:   Everything local. Use --post-summary/--post-findings to post.
  --pr <N>:          Findings posted as inline review. Summary local unless --post-summary.

Agents — full run
  Always:            pr-summarizer, code-reviewer
  Full-run-only:     architecture-reviewer, security-reviewer, blind-hunter, edge-case-hunter,
                     issue-linker (GitHub only)
  Conditional:       silent-failure-hunter, pr-test-analyzer, comment-analyzer, type-design-analyzer

Agents — --quick mode
  Always:            pr-summarizer (no diagrams), code-reviewer
  Conditional:       silent-failure-hunter, pr-test-analyzer (if patterns match)
  Skipped:           all full-run-only + comment-analyzer, type-design-analyzer, issue-linker

Agents — TIER=tiny (auto, <50 lines AND ≤3 files)
  Always:            pr-summarizer (Haiku), code-reviewer
  Conditional:       silent-failure-hunter, pr-test-analyzer (if patterns match)
                     architecture-reviewer (if infra/CI/cross-dir paths in diff)
                     security-reviewer (if auth/credential/dep-manifest paths in diff)
  Skipped:           blind-hunter, edge-case-hunter, comment-analyzer, type-design-analyzer,
                     issue-linker (GitHub-only conditions still apply)

Deterministic checks (all modes except --summary-only)
  dependency-check:  Queries OSV.dev for CVEs in changed dependency manifests.
                     Also runs in --security-only mode (CVE checks are security checks).
                     Triggers on: go.mod, package.json, requirements*.txt, composer.json.
                     Uses OSV /v1/querybatch for speed. No API key required.
                     Network failures are non-blocking.

claude-mem Integration (optional)
  When claude-mem is detected, the skill automatically stores a structured review
  summary to persistent memory and passes up to 5 prior review summaries as context
  to the architecture-reviewer and security-reviewer agents. Use --no-mem to opt out.
  No effect when claude-mem is not installed.

Examples
  /comprehensive-review                         Review current branch, everything local
  /comprehensive-review --create-pr             Review and create PR with summary
  /comprehensive-review --quick                 Fast review, skip expensive agents
  /comprehensive-review --post-findings         Post findings on existing own PR
  /comprehensive-review --pr 42                 Review someone else's PR #42
  /comprehensive-review --pr 42 --no-findings   Review PR #42 locally only
  /comprehensive-review --no-post               Skip all remote operations

Provider support
  Detected automatically from git remote URL. Override with --provider.
  GitHub / GitHub Enterprise:  Full support (gh CLI required)
  GitLab:                      Full support (glab CLI required)
  Bitbucket:                   PR creation, summary, comment posting.
                               Inline review comments not supported.
                               Requires BITBUCKET_TOKEN env var (or
                               BITBUCKET_APP_PASSWORD, auto-mapped).
