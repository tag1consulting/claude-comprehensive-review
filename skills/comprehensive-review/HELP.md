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
  --security-only    Run security-reviewer + CVE check (on changed dep manifests) only
  --summary-only     Run pr-summarizer only

  --create-pr        Create a PR using the summary (Block A) as the description
  --post-summary     Post summary (Block A) as a comment on an existing PR/MR.
                     Unaffected by --draft/--publish on its own; combined with
                     --post-findings in draft mode, it rides along inside that
                     same draft instead of a separate comment.
  --post-findings    Stage findings (Block B) as inline review on an existing own PR/MR.
                     Stages an editable draft by default (GitHub: pending review;
                     GitLab: draft notes) — visible only to you, nothing published
                     until you edit and submit it yourself in the web UI.
  --draft            Explicit no-op alias for the default drafting behavior of
                     --post-findings. Use to pin the behavior in scripts against
                     a future default change.
  --publish          Post immediately instead of staging a draft (today's
                     pre-1.13.0 behavior). Required on Bitbucket and for any
                     CI/scripted use — a bot cannot submit a draft from the web UI.
  --read-back        Read back your edited draft (GitHub/GitLab only), report what
                     you kept/edited/removed, and stage any newly-noticed findings
                     (GitLab: as additional draft notes; GitHub: reported in the
                     terminal only — its API can't append to an existing pending
                     review, so add them yourself in the web UI).
                     Requires an existing draft from a prior --post-findings run.
                     Costs the same as a full review — it re-runs analysis to
                     regenerate the findings it compares against.
                     Never publishes; never overwrites your edits.
  --no-findings      Suppress posting findings (useful for dry-run with --pr)
  --no-post / --local  Explicit alias for the default: skip all remote operations (no-post is the default; posting requires explicit flags)
  --pr <number>      Review an existing PR/MR by number (external review mode;
                     use --pr for all providers, including GitLab MRs)
  --depth <tier>     Agent depth: normal (default) or deep.
                     deep: blind-hunter and edge-case-hunter run on Opus,
                     Opus agents use extended step-by-step reasoning, and a
                     CVE reachability triage pass annotates which vulns are
                     actually reachable in the diff.
  --provider <name>  Override git provider detection (github, gitlab, bitbucket)
  --no-enrich-context  Disable symbol context enrichment (Grep-based cross-file definition
                     lookup). Context enrichment is on by default for all full runs except
                     TIER=tiny (<50 lines, ≤3 files) — it adds ~1-3K tokens per eligible
                     agent but reduces false positives by giving agents cross-file
                     definitions. Disable if you want to reduce token cost or the Grep
                     calls on large repos become slow.
  --no-mem           Disable claude-mem integration (auto-detected when available)
  --no-suppress      Disable all suppression rules (shows every finding; useful for audits)
  --min-confidence N Filter findings below confidence N (0–100; default 75; 0 disables). Applied
                     before suppression rules. See SEVERITY.md for the confidence scale.
  --output-file <p>  Write Block A + Block B to a markdown file at path <p> during Phase 5.
                     Use this to avoid re-running the review in a fresh session just to save
                     the output — saves ~$5–15 on large PRs where the post-review context
                     would otherwise force a new expensive session.

Default behavior
  All runs:          Everything local. No remote posting unless explicitly requested.
  No PR exists:      Use --create-pr to create one.
  Existing own PR:   Use --post-summary/--post-findings to post.
  --pr <N>:          Local only. Use --post-findings to post an inline review, --post-summary for a comment.
  --post-findings:   Stages an editable draft by default (GitHub/GitLab). Add --publish
                     to post immediately. Bitbucket always publishes (no verified draft
                     path yet) with a one-line notice.

Migration note (pre-1.13.0 -> 1.13.0)
  --post-findings alone used to publish immediately. It now stages a draft instead.
  Scripts/CI that expect immediate publishing must add --publish.

Agents — full run
  Always:            pr-summarizer, code-reviewer
  Full-run-only:     architecture-reviewer, security-reviewer, blind-hunter, edge-case-hunter,
                     issue-linker (GitHub only)
  Conditional:       silent-failure-hunter, pr-test-analyzer, comment-analyzer, type-design-analyzer

Agents — --quick mode
  Always:            pr-summarizer, code-reviewer
  Conditional:       silent-failure-hunter, pr-test-analyzer (if patterns match)
  Skipped:           all full-run-only + comment-analyzer, type-design-analyzer, issue-linker

Agents — TIER=tiny (auto, <50 lines AND ≤3 files)
  Always:            pr-summarizer (Haiku), code-reviewer
  Conditional:       silent-failure-hunter, pr-test-analyzer (if patterns match)
                     architecture-reviewer (if infra/CI/cross-dir paths in diff)
                     security-reviewer (if auth/credential/dep-manifest paths in diff)
  Skipped:           blind-hunter, edge-case-hunter, comment-analyzer, type-design-analyzer,
                     issue-linker (GitHub-only conditions still apply)

Auto-cheap routing (automatic, no flag needed)
  DOCS_ONLY          All changed files are docs/markdown/meta (no code or infra). Runs:
                     pr-summarizer + code-reviewer + triggered silent-failure-hunter/pr-test-analyzer
                     + CVE check if manifest files changed. Skips all Opus agents and
                     blind-hunter, edge-case-hunter, comment-analyzer, type-design-analyzer.
                     Phase 5 reports: "Auto-cheap: DOCS_ONLY — Opus agents skipped."
                     Overridden by: --depth deep, --quick, --security-only, --summary-only.

  LOW_RISK_CONFIG    Diff contains only config/YAML/TOML/INI with no security-sensitive
                     patterns (no auth/token/secret/exec keywords, no dep manifests, no
                     Dockerfile/CI paths). Runs: pr-summarizer + code-reviewer + deterministic
                     checks. Skips: architecture-reviewer, security-reviewer, blind-hunter,
                     edge-case-hunter, comment-analyzer, type-design-analyzer.
                     Phase 5 reports: "Auto-cheap: LOW_RISK_CONFIG — specialist agents skipped."

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
  /comprehensive-review --post-findings         Stage findings as your draft review (own PR)
  /comprehensive-review --post-findings --publish  Post findings immediately (own PR)
  /comprehensive-review --read-back             Read back your edited draft, flag what you missed
  /comprehensive-review --pr 42                        Review someone else's PR #42 locally
  /comprehensive-review --pr 42 --post-findings        Review PR #42, stage findings as a draft
  /comprehensive-review --pr 42 --post-findings --publish  Review PR #42 and publish inline findings
  /comprehensive-review --pr 42 --post-summary --post-findings --publish  Review PR #42, post both

Provider support
  Detected automatically from git remote URL. Override with --provider.
  GitHub / GitHub Enterprise:  Full support (gh CLI required). --post-findings
                               stages a pending review by default.
  GitLab:                      Full support (glab CLI required). --post-findings
                               stages draft notes by default.
  Bitbucket:                   PR creation, summary, comment posting.
                               Inline review comments not supported. No verified
                               draft-create path — --post-findings always publishes
                               a single PR comment, regardless of --draft/--publish.
                               Requires BITBUCKET_TOKEN env var (or
                               BITBUCKET_APP_PASSWORD, auto-mapped).
