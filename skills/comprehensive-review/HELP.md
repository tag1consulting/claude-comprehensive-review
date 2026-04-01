/comprehensive-review — Comprehensive PR Review

Run a full CodeRabbit-style review using specialized agents.

Usage
  /comprehensive-review [flags]

Flags
  --base <branch>    Compare against a different base branch (default: auto-detect or main)
  --quick            Fast mode: pr-summarizer + code-reviewer + triggered error/test agents.
                     Skips security, architecture, blind-hunter, edge-case-hunter, comment,
                     and type analysis. ~75% cheaper.
  --security-only    Run security-reviewer only
  --summary-only     Run pr-summarizer only

  --create-pr        Create a PR using the summary (Block A) as the description
  --post-summary     Post summary (Block A) as a comment on an existing PR
  --post-findings    Post findings (Block B) as inline review on an existing own PR
  --no-findings      Suppress posting findings (useful for dry-run with --pr)
  --no-post / --local  Skip all GitHub operations, display everything locally
  --pr <number>      Review an existing PR by number (external review mode)

  --help             Show this help

Default behavior
  No PR exists:      Everything local. Use --create-pr to create one.
  Existing own PR:   Everything local. Use --post-summary/--post-findings to post.
  --pr <N>:          Findings posted as inline review. Summary local unless --post-summary.

Agents — full run
  Always:            pr-summarizer, code-reviewer
  Full-run-only:     architecture-reviewer, security-reviewer, blind-hunter, edge-case-hunter
  Conditional:       silent-failure-hunter, pr-test-analyzer, comment-analyzer, type-design-analyzer
  Optional:          issue-linker

Agents — --quick mode
  Always:            pr-summarizer (no diagrams), code-reviewer
  Conditional:       silent-failure-hunter, pr-test-analyzer (if patterns match)
  Skipped:           all full-run-only + comment-analyzer, type-design-analyzer, issue-linker

Examples
  /comprehensive-review                         Review current branch, everything local
  /comprehensive-review --create-pr             Review and create PR with summary
  /comprehensive-review --quick                 Fast review, skip expensive agents
  /comprehensive-review --post-findings         Post findings on existing own PR
  /comprehensive-review --pr 42                 Review someone else's PR #42
  /comprehensive-review --pr 42 --no-findings   Review PR #42 locally only
  /comprehensive-review --no-post               Skip all GitHub operations
