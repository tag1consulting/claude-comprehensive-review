---
name: comprehensive-review
description: >
  Run a comprehensive CodeRabbit-style PR review using specialized agents.
  Produces a unified report with high-level summary, file walkthrough, sequence
  diagrams, related issue discovery, linked issue assessment, effort estimation,
  architectural insights, security analysis, and detailed per-file review comments.
  By default, creates the PR (or posts to existing PR) with the informational sections
  as the PR description or comment. Findings are displayed locally for the author.

  Use before opening a pull request. Available globally for all projects.
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Agent
  - mcp__github-pat__get_issue
  - mcp__github-pat__list_issues
  - mcp__github-pat__list_pull_requests
  - mcp__github-pat__get_pull_request
  - mcp__github-pat__search_issues
  - mcp__github-pat__search_code
---

# Comprehensive PR Review

Run a full CodeRabbit-style review of all changes on the current branch.

**Arguments:** `$ARGUMENTS`

Supported flags:
- `--base <branch>` — compare against a different base branch (default: auto-detect upstream or `main`)
- `--quick` — skip issue-linker and sequence diagrams (faster, ~half the time)
- `--security-only` — run security-reviewer only
- `--summary-only` — run pr-summarizer only
- `--no-post` / `--local` — display everything locally, skip all GitHub operations
- `--help` — show this usage

## Pre-flight Context

- **Repository:** !`git remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]\(.*\)\.git|\1|; s|.*github.com[:/]||'`
- **Branch:** !`git branch --show-current 2>/dev/null`
- **Upstream base:** !`git rev-parse --abbrev-ref HEAD@{upstream} 2>/dev/null | sed 's|origin/||' || echo "main"`
- **Changed files:** !`git diff --name-only main...HEAD 2>/dev/null | head -40`
- **Diff stats:** !`git diff --stat main...HEAD 2>/dev/null | tail -3`
- **Commit log:** !`git log --oneline main...HEAD 2>/dev/null | head -20`

## Review Workflow

### Phase 0: Pre-flight and Manifest Construction

1. Parse `$ARGUMENTS`:
   - Extract `--base <branch>` if present, otherwise use the detected upstream base, falling back to `main`
   - Note any mode flags: `--quick`, `--security-only`, `--summary-only`, `--no-post`/`--local`

2. Run `git diff --name-only <base>...HEAD` to confirm the changed file list.

3. If there are no changed files, report "No changes found between current branch and `<base>`" and stop.

4. **Build the file manifest** — run `git diff --stat <base>...HEAD` and construct a structured summary:
   - Detect languages from file extensions
   - Categorize each file: source, test, config, docs, dependency
   - Count total diff lines from the stat output
   - Format as a compact manifest:
     ```
     BASE: <base>  |  LANGUAGES: <detected>  |  FILES: <N>  |  LINES: +<added>/-<removed>

     Source:  path/to/file.go (+45/-12), path/to/other.go (+30/-5), ...
     Tests:   path/to/file_test.go (+20/-0)
     Config:  go.mod (+2/-1)
     Docs:    README.md (+10/-3)
     ```

5. **Read project context** — if CLAUDE.md exists in the repository root, read it and extract
   a condensed project-context block (architecture, conventions, key constraints — ~500 tokens max).
   Also check for CLAUDE.md in subdirectories of changed files.

6. **Capture the commit log** — store the output of `git log --oneline <base>...HEAD` (already
   available from pre-flight context). This will be passed to agents that need it, so they do
   not need to fetch it themselves.

7. **Determine diff size tier** — count the total lines from `git diff --stat`:
   - **Small** (under 500 lines): full diff will be passed inline to agents
   - **Medium/Large** (500+ lines): agents will receive the file manifest and read files selectively

8. Determine which agents to run (see Phase 1).

### Phase 1: Launch Agents in Parallel

#### Token-Efficient Context Passing

**Important: Do not display raw diffs to the user.** When you need to capture a diff (full or
per-file), write it to a temporary file, then read it with the Read tool:
```bash
git diff <base>...HEAD > /tmp/cr-diff-$$.txt
```
Use `$$` (shell PID) or a unique suffix to avoid collisions. This avoids flooding the
terminal with diff output.

**Small diffs (under 500 lines total):** Capture `git diff <base>...HEAD` once to a temp file,
read it, and pass the content inline to all agents. The overhead of agents reading files
individually exceeds the cost of including the diff at this size.

**Medium and large diffs (500+ lines):** Do NOT pass the full diff inline. Instead, each agent
receives:
- The **file manifest** (from Phase 0 step 4)
- The **base branch name** (so agents can run `git diff <base>...HEAD -- <file>` selectively)
- The **condensed project context** (from Phase 0 step 5)
- The **commit log** (from Phase 0 step 6) — only for agents that need it

Custom agents (pr-summarizer, issue-linker, security-reviewer, architecture-reviewer) will
use selective `git diff <base>...HEAD -- <specific-file>` reads to examine only the files
relevant to their analysis.

For pr-review-toolkit agents that we cannot modify (code-reviewer, silent-failure-hunter,
pr-test-analyzer, comment-analyzer, type-design-analyzer), pass **relevant file slices** of
the diff rather than the full diff:
- **code-reviewer** — full diff (general scope, cannot be meaningfully sliced)
- **silent-failure-hunter** — only diff for files containing error-handling patterns
- **pr-test-analyzer** — only diff for test files and their source counterparts
- **comment-analyzer** — only diff for files with comment changes
- **type-design-analyzer** — only diff for files with type/struct/interface definitions

To produce a file slice, write to a temp file and read it:
```bash
git diff <base>...HEAD -- <file1> <file2> ... > /tmp/cr-slice-$$.txt
```

#### Agent Roster

**Always-run agents** (unless a specific mode flag limits scope):

- **pr-summarizer** — pass the file manifest, commit log, and project context.
  For small diffs: also include the full diff inline.
  For medium/large diffs: the agent will read files selectively using the manifest.

- **code-reviewer** (pr-review-toolkit) — pass the full diff regardless of size tier
  (its general scope means slicing is not meaningful).

- **architecture-reviewer** — pass the file manifest, commit log, and project context.
  For small diffs: also include the full diff inline.
  For medium/large diffs: the agent will read files selectively using the manifest.

- **security-reviewer** — always run (security review is always warranted). Pass the file
  manifest, detected languages, and project context.
  For small diffs: also include the full diff inline.
  For medium/large diffs: the agent will read files selectively, prioritizing auth, crypto,
  input handling, and dependency files.

**Conditional agents** — include unless `--quick`:

- **issue-linker** — pass the commit log, branch name, file manifest, and GitHub repo slug
  (owner/repo). Does not receive the diff inline — it extracts keywords from commit messages
  and file names. It may use `git diff <base>...HEAD -- <file>` if it needs to verify
  specific code changes against an issue's requirements.

- **silent-failure-hunter** (pr-review-toolkit) — only if diff contains error handling patterns:
  look for `catch`, `if err`, `try {`, `rescue`, `Result<`, `unwrap`, `.error`.
  Pass only the diff for files containing these patterns.

- **pr-test-analyzer** (pr-review-toolkit) — only if any `*_test.go`, `test_*.py`, `*.test.ts`,
  `*.spec.ts`, `spec/`, or `__tests__/` files appear in the changed file list.
  Pass only the diff for test files and their likely source counterparts.

- **comment-analyzer** (pr-review-toolkit) — only if the diff adds or modifies comment lines
  (lines starting with `//`, `#`, `/*`, `*`, `"""`, `'''`).
  Pass only the diff for files with comment changes.

- **type-design-analyzer** (pr-review-toolkit) — only if the diff adds type/struct/interface
  definitions (look for `type ... struct`, `type ... interface`, `interface `, `class `, `enum `).
  Pass only the diff for files with type definitions.

Launch all applicable agents simultaneously using parallel Agent tool calls.

### Phase 2: Collect and Normalize Results

Wait for all agents to complete. Then normalize severity levels to a unified scale:

| Agent | Their Scale | Maps To |
|-------|-------------|---------|
| code-reviewer | confidence 91–100 | Critical |
| code-reviewer | confidence 80–90 | High |
| silent-failure-hunter | CRITICAL | Critical |
| silent-failure-hunter | HIGH | High |
| silent-failure-hunter | MEDIUM | Medium |
| pr-test-analyzer | gap rating 8–10 | Critical |
| pr-test-analyzer | gap rating 5–7 | High |
| pr-test-analyzer | gap rating 3–4 | Medium |
| pr-test-analyzer | gap rating 1–2 | Low |
| type-design-analyzer | rating < 3 | High |
| type-design-analyzer | rating 3–5 | Medium |
| type-design-analyzer | rating > 5 | Low |
| architecture-reviewer | pass through directly |
| security-reviewer | pass through directly |

Note: Custom agents (security-reviewer, architecture-reviewer) report Medium+ only.
Toolkit agents (pr-test-analyzer, type-design-analyzer) may still produce Low-severity findings.

Deduplicate: if two agents flag the same `file:line`, keep the highest severity entry
and add a note "(also flagged by [agent2])".

### Phase 3: Assemble the Reports

Build two separate output blocks:

#### Block A — Informational (will be posted to GitHub)

Assemble the pr-summarizer and issue-linker outputs into this format:

```markdown
## Summary

<from pr-summarizer>

**Type:** <type>
**Effort:** <N>/5 — <justification>

## Walkthrough

| File | Change | Summary |
|------|--------|---------|
<rows from pr-summarizer>

## Sequence Diagrams

<from pr-summarizer>

## Related Issues & PRs

<from issue-linker, or omitted if --quick was used>
```

#### Block B — Findings (local terminal output only, never posted to GitHub)

```markdown
---

## Review Findings

**Overall Risk:** <Critical|High|Medium|Low> — based on worst severity found

### Critical (<N>)
- **[agent]** <finding> — `file:line`

### High (<N>)
- **[agent]** <finding> — `file:line`

### Medium (<N>)
- **[agent]** <finding> — `file:line`

### Low (<N>)
- **[agent]** <finding> — `file:line`

### Architectural Insights

<condensed output from architecture-reviewer>

### Security Analysis

<condensed output from security-reviewer>

### Positive Observations

<aggregated from all agents>

### Recommended Actions

1. <prioritized list of what to fix before the PR goes out for review>
2. ...

---
```

### Phase 4: PR Creation and Summary Comment

**Skip Phase 4 entirely if `--no-post` or `--local` was passed.**

Check whether a PR already exists for the current branch:

```bash
gh pr view --json number,title,body 2>/dev/null
```

**If NO PR exists:**
Create the PR with Block A as the description. Use a concise title from the Summary (under 70 chars).
Capture the PR URL from the output for Phase 5 reporting.

```bash
gh pr create --title "<title>" --base "<base>" --body "$(cat <<'PREOF'
<Block A content>
PREOF
)"
```

**If a PR already exists:**
Post Block A as a PR comment. Check the existing body for `## Summary` and `## Walkthrough`:
- If NOT present (first run): use `## PR Review Summary` as the heading
- If already present (re-run): use `## PR Review Summary (Updated)` as the heading

```bash
gh pr comment --body "$(cat <<'CEOF'
## PR Review Summary            ← or "## PR Review Summary (Updated)" on re-runs
<Block A content>
CEOF
)"
```

### Phase 5: Final Output

Display to the user in the terminal:

1. If Phase 4 ran:
   - "PR created/updated: <URL>" (or "Summary comment posted to PR #<N>")

2. Always display Block B (findings) in the terminal.

3. If there are Critical or High findings:
   - "⚠ Address the Critical/High findings above before requesting review."

4. If there are no findings:
   - "No significant issues found. This PR is ready for review."

## Notes

- This skill runs globally and is project-agnostic. The orchestrator reads CLAUDE.md at pre-flight and passes a condensed project context to agents — agents should not read CLAUDE.md themselves unless they need additional detail from subdirectory CLAUDE.md files.
- The pr-review-toolkit agents (code-reviewer, silent-failure-hunter, etc.) are reused as-is.
- GitHub write operations use `gh` CLI. GitHub read operations may use either `gh` or the GitHub MCP tools.
- Never post findings to GitHub — those are for the author's eyes only until fixed.
