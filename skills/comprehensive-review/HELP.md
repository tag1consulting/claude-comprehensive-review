/comprehensive-review — Comprehensive PR/MR Review

Run a full CodeRabbit-style review using specialized agents.
Supports GitHub (including Enterprise), GitLab, and Bitbucket.

Usage
  /comprehensive-review [flags]

Flags
  --base <branch>    Compare against a different base branch (default: auto-detect or main)
  --quick            Fast mode: pr-summarizer + code-reviewer + triggered error/test agents.
                     Skips security, architecture, blind-hunter, edge-case-hunter, comment,
                     and type analysis. ~75% cheaper.
  --diagrams         Include Mermaid sequence diagrams in the summary (default: omitted;
                     always omitted in --quick)
  --security-only    Run security-reviewer only
  --summary-only     Run pr-summarizer only

  --create-pr        Create a PR using the summary (Block A) as the description
  --post-summary     Post summary (Block A) as a comment on an existing PR/MR
  --post-findings    Post findings (Block B) as inline review on an existing own PR/MR
  --no-findings      Suppress posting findings (useful for dry-run with --pr)
  --no-post / --local  Skip all remote operations and issue-linker, display everything locally
  --pr <number>      Review an existing PR/MR by number (external review mode;
                     use --pr for all providers, including GitLab MRs)
  --provider <name>  Override git provider detection (github, gitlab, bitbucket)
  --no-mem           Disable claude-mem integration (auto-detected when available)

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
