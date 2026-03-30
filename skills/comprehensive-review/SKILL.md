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

### Phase 0: Pre-flight

1. Parse `$ARGUMENTS`:
   - Extract `--base <branch>` if present, otherwise use the detected upstream base, falling back to `main`
   - Note any mode flags: `--quick`, `--security-only`, `--summary-only`, `--no-post`/`--local`

2. Run `git diff --name-only <base>...HEAD` to confirm the changed file list.

3. If there are no changed files, report "No changes found between current branch and `<base>`" and stop.

4. Determine which agents to run (see Phase 1).

### Phase 1: Launch Agents in Parallel

**Always-run agents** (unless a specific mode flag limits scope):
- **pr-summarizer** — pass the full `git diff <base>...HEAD` output, the changed file list, and `git log --oneline <base>...HEAD`
- **code-reviewer** (pr-review-toolkit) — pass the diff for general code quality review
- **architecture-reviewer** — pass the diff and note the location of CLAUDE.md files

**Conditional agents** — include unless `--quick`:
- **issue-linker** — pass commit messages, branch name, and the GitHub repo slug (owner/repo)

**Conditional agents** — based on what changed:
- **security-reviewer** — always run (security review is always warranted)
- **silent-failure-hunter** (pr-review-toolkit) — only if diff contains error handling patterns:
  look for `catch`, `if err`, `try {`, `rescue`, `Result<`, `unwrap`, `.error`
- **pr-test-analyzer** (pr-review-toolkit) — only if any `*_test.go`, `test_*.py`, `*.test.ts`,
  `*.spec.ts`, `spec/`, or `__tests__/` files appear in the changed file list
- **comment-analyzer** (pr-review-toolkit) — only if the diff adds or modifies comment lines
  (lines starting with `//`, `#`, `/*`, `*`, `"""`, `'''`)
- **type-design-analyzer** (pr-review-toolkit) — only if the diff adds type/struct/interface
  definitions (look for `type ... struct`, `type ... interface`, `interface `, `class `, `enum `)

Launch all applicable agents simultaneously using parallel Agent tool calls. Each agent
receives the relevant portion of the diff as part of its prompt. For diffs over 3000 lines,
pass only the diff for files relevant to each agent's specialty.

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
1. Create the PR using `gh pr create`, passing Block A as the PR description body.
   Use a concise title derived from the Summary section (under 70 characters).
   Set the base branch to the detected `<base>`.

   ```bash
   gh pr create --title "<title>" --base "<base>" --body "$(cat <<'PREOF'
   <Block A content>
   PREOF
   )"
   ```

2. Report the PR URL to the user.

**If a PR already exists:**
1. Check whether the PR description body already contains the informational sections
   (look for `## Summary` and `## Walkthrough` in the existing body).

2. If NOT already present:
   Post Block A as a PR comment:
   ```bash
   gh pr comment --body "$(cat <<'CEOF'
   ## PR Review Summary
   <Block A content>
   CEOF
   )"
   ```

3. If already present (previous run):
   Post an updated Block A as a new PR comment with a note:
   ```bash
   gh pr comment --body "$(cat <<'CEOF'
   ## PR Review Summary (Updated)
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

- This skill runs globally and is project-agnostic. Agents read CLAUDE.md at runtime for project-specific context.
- The pr-review-toolkit agents (code-reviewer, silent-failure-hunter, etc.) are reused as-is.
- GitHub write operations use `gh` CLI. GitHub read operations may use either `gh` or the GitHub MCP tools.
- Never post findings to GitHub — those are for the author's eyes only until fixed.
