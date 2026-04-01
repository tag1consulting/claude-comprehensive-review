---
name: comprehensive-review
description: >
  Run a comprehensive CodeRabbit-style PR review using specialized agents.
  Produces a structured PR summary and a findings report. Supports reviewing
  your own branch (pre-PR) or an existing PR by number (--pr <N>).

  Default behavior:
    No PR exists:      Creates PR with Block A as description; findings shown locally only.
    Existing own PR:   Everything shown locally. Use --post-summary/--post-findings to post.
    --pr <N>:          Findings posted as inline review; summary local unless --post-summary.

  Use before opening a pull request or to review an existing PR.
  Available globally for all projects.
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
  - mcp__github-pat__create_pull_request_review
  - mcp__github-pat__get_pull_request_files
---

# Comprehensive PR Review

Run a full CodeRabbit-style review of all changes on the current branch (or a specified PR).

**Arguments:** `$ARGUMENTS`

Supported flags:
- `--base <branch>` — compare against a different base branch (default: auto-detect upstream or `main`)
- `--quick` — fast mode: pr-summarizer + code-reviewer + triggered error/test agents only; skips security, architecture, blind-hunter, edge-case-hunter, comment, and type analysis (~65%+ cheaper)
- `--security-only` — run security-reviewer only
- `--summary-only` — run pr-summarizer only
- `--post-summary` — post Block A (informational summary) as a comment on an existing PR
- `--post-findings` — post Block B (findings) as inline GitHub review on an existing own PR
- `--no-findings` — suppress posting findings as a review (useful for dry-run with `--pr`)
- `--no-post` / `--local` — display everything locally, skip all GitHub operations
- `--pr <number>` — review an existing PR by number (external review mode)
- `--help` — show this usage

## Pre-flight Context

- **Repository:** !`git remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]\(.*\)\.git|\1|; s|.*github.com[:/]||'`
- **Branch:** !`git branch --show-current 2>/dev/null`
- **Upstream base:** !`git rev-parse --abbrev-ref HEAD@{upstream} 2>/dev/null | sed 's|origin/||' || echo "main"`
- **Changed files:** !`BASE=$(git rev-parse --abbrev-ref HEAD@{upstream} 2>/dev/null | sed 's|origin/||' || echo "main"); git diff --name-only "$BASE...HEAD" 2>/dev/null | head -40`
- **Diff stats:** !`BASE=$(git rev-parse --abbrev-ref HEAD@{upstream} 2>/dev/null | sed 's|origin/||' || echo "main"); git diff --stat "$BASE...HEAD" 2>/dev/null | tail -3`
- **Commit log:** !`BASE=$(git rev-parse --abbrev-ref HEAD@{upstream} 2>/dev/null | sed 's|origin/||' || echo "main"); git log --oneline "$BASE...HEAD" 2>/dev/null | head -20`

## Review Workflow

### Phase 0: Pre-flight and Manifest Construction

1. Parse `$ARGUMENTS`:
   - If `--help` is present, display the help text below and **stop immediately** — do not continue.
   - Extract `--base <branch>` if present, otherwise use the detected upstream base, falling back to `main`
   - Extract `--pr <number>` if present — set PR_NUMBER and enable external review mode
   - Note mode flags: `--quick`, `--security-only`, `--summary-only`, `--no-post`/`--local`,
     `--post-summary`, `--post-findings`, `--no-findings`
   - **Flag conflict check:** if both `--post-findings` and `--no-findings` are present, report
     "Error: --post-findings and --no-findings are mutually exclusive." and stop.

**Help text (display when `--help` is passed):**

```
/comprehensive-review — Comprehensive PR Review

Run a full CodeRabbit-style review using specialized agents.

Usage
  /comprehensive-review [flags]

Flags
  --base <branch>    Compare against a different base branch (default: auto-detect or main)
  --quick            Fast mode: run only pr-summarizer + code-reviewer + triggered
                     error/test agents. Skips security, architecture, blind-hunter,
                     edge-case-hunter, comment, and type analysis. ~65%+ cheaper than full run.
  --security-only    Run security-reviewer only
  --summary-only     Run pr-summarizer only

  --post-summary     Post the informational summary (Block A) as a comment on an existing PR
  --post-findings    Post findings (Block B) as inline review comments on an existing own PR
  --no-findings      Suppress posting findings on external PR reviews (--pr mode)
  --no-post / --local  Skip all GitHub operations, display everything locally
  --pr <number>      Review an existing PR by number (external review mode)

  --help             Show this help

Default behavior
  No PR exists:      Creates PR with summary as description. Findings shown locally.
  Existing own PR:   Everything shown locally. Use --post-summary and/or --post-findings to post.
  --pr <N>:          Findings posted as inline review (REQUEST_CHANGES if Medium+, COMMENT if Low only).
                     Summary shown locally unless --post-summary is also passed.

Agents — full run
  Always:            pr-summarizer, code-reviewer
  Full-run-only:     architecture-reviewer, security-reviewer, blind-hunter, edge-case-hunter
  Conditional:       silent-failure-hunter, pr-test-analyzer, comment-analyzer, type-design-analyzer
  Optional:          issue-linker

Agents — --quick mode
  Always:            pr-summarizer (no diagrams), code-reviewer
  Conditional:       silent-failure-hunter, pr-test-analyzer (if patterns match)
  Skipped:           architecture-reviewer, security-reviewer, blind-hunter, edge-case-hunter,
                     comment-analyzer, type-design-analyzer, issue-linker

Examples
  /comprehensive-review                         Review current branch, create PR if needed
  /comprehensive-review --quick                 Fast review, skip expensive agents
  /comprehensive-review --post-findings         Review + post findings on existing own PR
  /comprehensive-review --pr 42                 Review someone else's PR #42
  /comprehensive-review --pr 42 --post-summary  Review PR #42 and also post summary comment
  /comprehensive-review --pr 42 --no-findings   Review PR #42 locally, skip findings post
  /comprehensive-review --no-post               Review locally, skip all GitHub operations
```

2. **If `--pr <N>` was passed** (external review mode):

   a. Fetch PR metadata:
      ```bash
      gh pr view <N> --json number,title,baseRefName,headRefName,state
      ```
   b. If PR state is `CLOSED` or `MERGED`, report "PR #<N> is <state> — cannot review a closed PR." and stop.
   c. Set BASE to the PR's `baseRefName`.
   d. Create a temporary worktree and check out the PR branch:
      ```bash
      WORKTREE_PATH=$(mktemp -d /tmp/cr-pr-XXXXXXXX)
      rmdir "$WORKTREE_PATH"   # mktemp creates the dir; worktree add needs it absent
      git worktree add "$WORKTREE_PATH" --detach || {
        echo "Error: failed to create worktree at $WORKTREE_PATH" >&2
        exit 1
      }
      (cd "$WORKTREE_PATH" && gh pr checkout <N>) || {
        git worktree remove "$WORKTREE_PATH" --force 2>/dev/null
        echo "Error: failed to check out PR #<N> into worktree" >&2
        exit 1
      }
      ```
      Track WORKTREE_PATH for cleanup in Phase 5.
   e. All subsequent `git diff`, `git log`, and `git show` commands in this workflow must use
      `git -C "$WORKTREE_PATH"` to operate against the PR branch, not the invoking branch.

   **Note:** The pre-flight context above reflects the invoking branch, not the PR branch.
   The actual diff and branch context come from the worktree.

3. Run `git diff --name-only <base>...HEAD` to confirm the changed file list.
   In `--pr` mode, prefix with `git -C "$WORKTREE_PATH"`: `git -C "$WORKTREE_PATH" diff --name-only <base>...HEAD`
   All `git diff`, `git log`, and `git show` commands from this point forward use `git -C "$WORKTREE_PATH"` in `--pr` mode.

4. If there are no changed files, report "No changes found between current branch and `<base>`" and stop.

5. **Build the file manifest** — run `git diff --stat <base>...HEAD` and construct a structured summary:
   - Detect languages from file extensions
   - Categorize each file into exactly one of: **Source**, **Tests**, **Config**, **Docs**, **Dependency**
     (Source = application/library code; Tests = test files; Config = build/CI/tool config;
     Docs = documentation/markdown; Dependency = package manifests like go.mod, package.json, Gemfile)
   - Count total changed lines (insertions + deletions) from the stat output
   - Format as a compact manifest (LANGUAGES is comma-separated, capitalized):
     ```
     BASE: <base>  |  LANGUAGES: Go, TypeScript  |  FILES: <N>  |  LINES: +<added>/-<removed>

     Source:  path/to/file.go (+45/-12), path/to/other.go (+30/-5), ...
     Tests:   path/to/file_test.go (+20/-0)
     Config:  .github/workflows/ci.yml (+5/-2)
     Deps:    go.mod (+2/-1)
     Docs:    README.md (+10/-3)
     ```
     Omit categories with no files. For binary or generated files, list under a **Other** category.

6. **Read project context** — if CLAUDE.md exists in the repository root, read it and extract
   a condensed project-context block (architecture, conventions, key constraints — ~500 tokens max).
   Also check for CLAUDE.md in subdirectories of changed files.
   If no CLAUDE.md exists, set the project context to: "No project-specific context available.
   Apply general best practices."

7. **Capture the commit log** — store the output of `git log --oneline <base>...HEAD` (already
   available from pre-flight context for own-branch reviews; captured fresh for `--pr` mode).
   This will be passed to agents that need it, so they do not need to fetch it themselves.

8. **Determine diff size tier** — count total changed lines (insertions + deletions) from
   `git diff --stat`. 500 lines is approximately 2K tokens of diff; below this, inline
   passing costs less than multiple selective `git diff -- <file>` tool calls.
   - **Small** (under 500 changed lines): full diff will be passed inline to agents
   - **Medium/Large** (500+ changed lines): agents will receive the file manifest and read files selectively
   - If the line count cannot be reliably determined, default to **Medium/Large** (selective
     reads are always safe; passing a too-large diff inline risks blowing context windows)

9. Determine which agents to run (see Phase 1).

### Phase 1: Launch Agents in Parallel

#### Token-Efficient Context Passing

**Important: Do not display raw diffs to the user.** When you need to capture a diff (full or
per-file), write it to a temporary file using `mktemp`, then read it with the Read tool:
```bash
DIFF_FILE=$(mktemp /tmp/cr-diff-XXXXXXXX.txt)
git diff <base>...HEAD > "$DIFF_FILE"
```
`mktemp` creates files with unpredictable names and mode 0600, avoiding symlink attacks and
collisions. Track all created temp files for cleanup in Phase 5.

**Small diffs (under 500 lines total):** Capture `git diff <base>...HEAD` once to a temp file,
read it, and pass the content inline to all agents. The overhead of agents reading files
individually exceeds the cost of including the diff at this size.

**Medium and large diffs (500+ lines):** Do NOT pass the full diff inline. Instead, each agent
receives:
- The **file manifest** (from Phase 0 step 5)
- The **base branch name** (so agents can run `git diff <base>...HEAD -- <file>` selectively)
- The **condensed project context** (from Phase 0 step 6)
- The **commit log** (from Phase 0 step 7) — only for agents that need it

Custom agents (pr-summarizer, issue-linker, security-reviewer, architecture-reviewer,
edge-case-hunter) will use selective `git diff <base>...HEAD -- <specific-file>` reads to
examine only the files relevant to their analysis.

**Exception: blind-hunter receives only the raw diff or a plain file list — not the
structured manifest or project context.** See the blind-hunter entry in the full-run-only
agents section below.

For pr-review-toolkit agents that we cannot modify (code-reviewer, silent-failure-hunter,
pr-test-analyzer, comment-analyzer, type-design-analyzer), pass **relevant file slices** of
the diff rather than the full diff:
- **code-reviewer** — full diff (general scope, cannot be meaningfully sliced)
- **silent-failure-hunter** — only diff for files containing error-handling patterns
- **pr-test-analyzer** — only diff for test files and their source counterparts
- **comment-analyzer** — only diff for files with comment changes
- **type-design-analyzer** — only diff for files with type/struct/interface definitions

To produce a file slice, write to a temp file with a per-agent suffix and read it:
```bash
SLICE_FILE=$(mktemp /tmp/cr-slice-sfh-XXXXXXXX.txt)   # sfh = silent-failure-hunter
git diff <base>...HEAD -- <file1> <file2> ... > "$SLICE_FILE"
```
Use a different suffix for each agent's slice (e.g., `cr-slice-sfh-`, `cr-slice-ca-`,
`cr-slice-tda-`). After writing a slice file, verify it is non-empty before launching
the corresponding agent. If the slice is empty, skip that agent.

#### Agent Roster

**Mode flag effects:**

| Flag | Agents that run |
|------|-----------------|
| (none) | All always-run + all triggered conditional agents |
| `--quick` | pr-summarizer (no diagrams) + code-reviewer + triggered silent-failure-hunter and pr-test-analyzer |
| `--security-only` | security-reviewer only |
| `--summary-only` | pr-summarizer only |

**Always-run agents** (in all modes unless `--security-only` or `--summary-only` limits scope):

- **pr-summarizer** — pass the file manifest, commit log, and project context.
  For small diffs: also include the full diff inline.
  For medium/large diffs: the agent will read files selectively using the manifest.
  **In `--quick` mode:** add the instruction "Note: --quick mode active. Omit the Sequence Diagrams section entirely."

- **code-reviewer** (pr-review-toolkit) — pass the full diff regardless of size tier
  (its general scope means slicing is not meaningful).

**Full-run-only agents** (skipped when `--quick` is passed):

- **architecture-reviewer** — pass the file manifest, commit log, and project context.
  For small diffs: also include the full diff inline.
  For medium/large diffs: the agent will read files selectively using the manifest.

- **security-reviewer** — pass the file manifest, commit log, detected languages, and project context.
  For small diffs: also include the full diff inline.
  For medium/large diffs: the agent will read files selectively, prioritizing auth, crypto,
  input handling, and dependency files.

- **blind-hunter** — **CRITICAL CONSTRAINT: pass ONLY the diff. Do NOT include the file
  manifest, project context, commit log, or any other context material.** The agent's
  value depends entirely on receiving zero project context — it catches issues that
  familiarity blinds the other agents to.
  For small diffs: pass only the full diff content inline.
  For medium/large diffs (non-`--pr` mode): pass only the base branch name and a plain
  file list (from `git diff --name-only <base>...HEAD`, NOT the categorized manifest
  with languages/categories/line counts). The agent uses `git diff <base>...HEAD -- <file>`
  to read files selectively.
  For medium/large diffs in `--pr` mode: the orchestrator must collect per-file diffs
  itself using `git -C "$WORKTREE_PATH" diff <base>...HEAD -- <file>` for each file,
  concatenate them into a temp file, and pass that content inline — do NOT rely on the
  agent to run git commands, as it has no knowledge of WORKTREE_PATH.

- **edge-case-hunter** — pass the file manifest, commit log, and project context.
  For small diffs: also include the full diff inline.
  For medium/large diffs: the agent will read files selectively using the manifest.
  This agent has full codebase read access and may use the Read tool to examine
  surrounding code context beyond the diff.

**Conditional agents — triggered by diff content, run in both full and `--quick` modes:**

To detect trigger patterns for medium/large diffs without loading the full diff into the
conversation, grep the temp diff file directly:
```bash
grep -l 'catch\|if err\|try {\|rescue\|Result<\|unwrap\|\.error\|\.expect(\|?\|runCatching\|guard\|throws' "$DIFF_FILE"
```
Do NOT read the diff file into the conversation for this check — just use grep to determine
whether each agent should launch.

- **silent-failure-hunter** (pr-review-toolkit) — only if diff contains error handling patterns:
  `catch`, `if err`, `try {`, `rescue`, `Result<`, `unwrap`, `.error`, `.expect(`, `?`
  (Rust), `runCatching`, `guard`, `throws`.
  Pass only the diff for files containing these patterns.

- **pr-test-analyzer** (pr-review-toolkit) — only if any `*_test.go`, `test_*.py`, `*.test.ts`,
  `*.spec.ts`, `spec/`, or `__tests__/` files appear in the changed file list.
  Pass only the diff for test files and their likely source counterparts.

**Conditional agents — full-run only** (skip in `--quick` and when not triggered):

- **comment-analyzer** (pr-review-toolkit) — only if the diff adds or modifies comment lines
  (lines starting with `//`, `#`, `/*`, `*`, `"""`, `'''`).
  Pass only the diff for files with comment changes.

- **type-design-analyzer** (pr-review-toolkit) — only if the diff adds type/struct/interface
  definitions (look for `type ... struct`, `type ... interface`, `interface `, `class `, `enum `).
  Pass only the diff for files with type definitions.

- **issue-linker** — pass the commit log, branch name, base branch name, file manifest, and
  GitHub repo slug (owner/repo). Does not receive the diff inline — it extracts keywords from
  commit messages and file names. It may use `git diff <base>...HEAD -- <file>` if it needs
  to verify specific code changes against an issue's requirements.
  **Skip in `--quick` mode and in `--pr` mode** (issue context is less relevant for external reviews).

Track which agents were skipped and why (pattern not triggered vs. `--quick` mode) for Phase 5 reporting.

Launch all applicable agents simultaneously using parallel Agent tool calls.

### Phase 2: Collect and Normalize Results

Wait for all agents to complete. **Check each agent's output before proceeding:**

1. If an agent returned structured output matching its expected format, proceed with normalization.
2. If an agent returned empty output or output missing expected section headers (e.g., no
   `## Security Analysis`, no `## Architectural Analysis`), flag it:
   "WARNING: <agent-name> returned no results. This may indicate an analysis failure rather
   than a clean result. Consider re-running with the relevant `--*-only` flag."
3. If an agent call itself failed (tool error, timeout), flag it:
   "ERROR: <agent-name> failed to execute. Reason: <error>. Findings from this agent are
   missing from the report."
4. Track the number of agents that failed or returned empty results for Phase 5.

**Normalize severity levels** to a unified scale (inclusive ranges):

| Agent | Their Scale | Maps To |
|-------|-------------|---------|
| code-reviewer | confidence [91, 100] | Critical |
| code-reviewer | confidence [80, 90] | High |
| code-reviewer | confidence [0, 79] | Medium |
| silent-failure-hunter | CRITICAL | Critical |
| silent-failure-hunter | HIGH | High |
| silent-failure-hunter | MEDIUM | Medium |
| comment-analyzer | Critical/High/Medium/Low | pass through directly |
| pr-test-analyzer | gap rating [8, 10] | Critical |
| pr-test-analyzer | gap rating [5, 7] | High |
| pr-test-analyzer | gap rating [3, 4] | Medium |
| pr-test-analyzer | gap rating [1, 2] | Low |
| type-design-analyzer | rating [1, 2] | High |
| type-design-analyzer | rating [3, 5] | Medium |
| type-design-analyzer | rating [6, 10] | Low |
| architecture-reviewer | Critical/High/Medium | pass through directly |
| security-reviewer | Critical/High/Medium | pass through directly |
| blind-hunter | Critical/High/Medium/Low | pass through directly |
| edge-case-hunter | Critical/High/Medium/Low | pass through directly |

Note: security-reviewer and architecture-reviewer report Medium+ only (Low findings omitted by design).
blind-hunter and edge-case-hunter report all four severity levels (Critical/High/Medium/Low).
Toolkit agents (pr-test-analyzer, type-design-analyzer) may also produce Low-severity findings.

**Deduplicate:** if two agents flag the same `file:line`, keep the highest severity entry
and add a note "(also flagged by [agent2])". For findings that reference a file without
a specific line number, deduplicate by `file` + finding category.

**Collect findings as structured data.** For each finding, record:
```
{
  severity:    "Critical" | "High" | "Medium" | "Low"
  agent:       <agent-name>
  file:        <relative-file-path> or null
  line:        <integer> or null
  finding:     <description text>
  remediation: <remediation text if provided by agent, otherwise null>
}
```
This structured list is used to render Block B (markdown display) and to build the inline
comment array in Phase 4b. The markdown format of each finding is unchanged:
`- **[agent]** <finding> — \`file:line\``

### Phase 3: Assemble the Reports

Build two separate output blocks:

#### Block A — Informational (conditionally posted to GitHub)

Assemble the pr-summarizer and issue-linker outputs into this format.
**If `--quick` was passed, omit the `## Sequence Diagrams` section** (pr-summarizer was told not to generate it):

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

<from pr-summarizer — omit this section entirely if --quick was passed>

## Related Issues & PRs

<from issue-linker, or omit if issue-linker was skipped>
```

#### Block B — Findings (always displayed in terminal; optionally posted to GitHub as a review)

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

<condensed output from architecture-reviewer, or omit if skipped>

### Security Analysis

<condensed output from security-reviewer, or omit if skipped>

### Positive Observations

<aggregated from all agents>

### Recommended Actions

1. <prioritized list of what to fix before the PR goes out for review>
2. ...

---
```

### Phase 4: PR Operations

**Skip Phase 4 entirely if `--no-post` or `--local` was passed.**

Determine the PR state and set posting variables:

```
If --pr mode:
  PR already exists (fetched in Phase 0) — set PR_NUMBER from --pr arg
  POST_SUMMARY = (--post-summary was passed)
  POST_FINDINGS = (--no-findings was NOT passed)

Else (own-branch mode):
  gh pr view --json number,title,body

  If command fails with "no pull requests found":
    PR_EXISTS = false
    POST_SUMMARY = false  (creating the PR IS posting the summary)
    POST_FINDINGS = false  (never post findings on new PR creation)
    If --post-findings was passed, warn: "Note: --post-findings has no effect when no PR exists.
    Findings will be shown locally. Create a PR first, then re-run with --post-findings."
    If --post-summary was passed, warn: "Note: --post-summary has no effect when no PR exists.
    The summary will be used as the new PR's description."

  If command fails for any other reason (auth, network, permissions):
    Report "GitHub API error: <error>. Use --no-post to skip GitHub operations." and skip Phase 4.

  If command succeeds (PR exists):
    PR_EXISTS = true
    PR_NUMBER = <number from json output>
    POST_SUMMARY = (--post-summary was passed)
    POST_FINDINGS = (--post-findings was passed)
```

**Create new PR (own-branch mode, no PR exists):**
Use a concise title from the Summary (under 70 chars). Capture the PR URL for Phase 5.

```bash
gh pr create --title "<title>" --base "<base>" --body "$(cat <<'PREOF'
<Block A content>
PREOF
)"
```

**Post Block A as comment (if POST_SUMMARY is true):**
Check the existing PR body for `## Summary` and `## Walkthrough`:
- If NOT present (first run): use `## PR Review Summary` as the heading
- If already present (re-run): use `## PR Review Summary (Updated)` as the heading

```bash
gh pr comment <PR_NUMBER> --body "$(cat <<'CEOF'
## PR Review Summary
<Block A content>
CEOF
)"
```

### Phase 4b: Post Findings as Inline Review

**Skip if POST_FINDINGS is false or `--no-post`/`--local` was passed.**

1. **Parse the diff for valid inline comment targets.** A GitHub inline comment can only be placed
   on lines that appear in the diff (added, deleted, or context lines). Parse the diff to build
   a per-file lookup of valid line numbers:

   - The diff is already captured in DIFF_FILE from Phase 1. Read it.
   - For each hunk header `@@ -old_start,old_count +new_start,new_count @@`, the RIGHT-side
     (new file) lines `new_start` through `new_start + new_count - 1` are valid comment targets.
   - Build a lookup: `{file_path → set of valid line numbers}`

2. **Partition findings into two groups:**
   - **INLINE:** findings where `file` and `line` are both set, and `line` is in the valid set
     for that file → will become an inline comment
   - **BODY:** findings where `file` is null, `line` is null, OR the line is not in the diff
     → will appear in the review body text

3. **Apply the 25-comment cap:**
   - Sort INLINE findings by severity: Critical → High → Medium → Low
   - Take the top 25 for inline comments
   - Move remaining INLINE findings to the BODY group with the note:
     "(inline comment limit reached — remaining findings listed here)"

4. **Determine the review event:**
   - **Own PR** (`--post-findings`): always use `"COMMENT"` (GitHub rejects `APPROVE` and it's
     inappropriate to `REQUEST_CHANGES` on your own PR)
   - **External PR** (`--pr` mode): use `"REQUEST_CHANGES"` if any Critical, High, or Medium
     findings exist; use `"COMMENT"` if only Low findings exist

5. **Build the review body:**
   ```markdown
   ## Comprehensive Review Findings

   **Overall Risk:** <severity>
   **Review mode:** <--quick if applicable, else full>
   **Agents:** <comma-separated list of agents that ran>

   ### Findings not attached to specific lines
   <BODY findings as markdown list, or "None — all findings are attached inline." if BODY is empty>
   ```

6. **Build the comments array.** Each entry:
   ```json
   {
     "path": "<relative file path>",
     "line": <line number>,
     "body": "**[Severity]** **[agent-name]** Finding description.\n\n**Remediation:** <remediation text, or omit if null>"
   }
   ```

7. **Submit the review** using `mcp__github-pat__create_pull_request_review`:
   - `owner`: repo owner from pre-flight
   - `repo`: repo name from pre-flight
   - `pull_number`: PR_NUMBER
   - `event`: determined in step 4
   - `body`: review body from step 5
   - `comments`: array from step 6

   **If the MCP tool fails**, fall back to `gh api`:
   ```bash
   REVIEW_BODY=$(cat <<'RBEOF'
   <review body>
   RBEOF
   )
   COMMENTS_JSON='[<json comments array>]'
   gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/reviews \
     -f event="<event>" \
     -f body="$REVIEW_BODY" \
     -F comments="$COMMENTS_JSON"
   ```

8. Report (for Phase 5): "Review posted to PR #<N>: <N> inline findings, <M> findings in review body"

### Phase 5: Final Output

**Cleanup:** Remove all temporary diff and slice files created during this run.
```bash
rm -f "$DIFF_FILE" "$SLICE_FILE_1" "$SLICE_FILE_2" ...
```

**If `--pr` mode:** Remove the temporary worktree created in Phase 0.
```bash
git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || true
```

Display to the user in the terminal:

1. If a new PR was created: "PR created: <URL>"
2. If Block A was posted as a comment: "Summary comment posted to PR #<N>"
3. If Phase 4b ran: "Review posted to PR #<N>: <N> inline findings, <M> in review body"
4. Always display Block B (findings) in the terminal.
5. Report skipped agents in two categories:
   - "--quick mode skipped: <agent-name>, <agent-name>" (if `--quick`)
   - "Skipped (no matching patterns in diff): <agent-name>, <agent-name>"
6. If there are Critical or High findings:
   - "⚠ Address the Critical/High findings above before requesting review."
7. If any agents failed or returned empty results (from Phase 2 checks):
   - "⚠ Review incomplete — <N> agent(s) failed or returned empty results.
     Do not treat this review as comprehensive."
8. If there are no findings AND no agent failures:
   - "No significant issues found. This PR is ready for review."

## Notes

- This skill runs globally and is project-agnostic. The orchestrator reads CLAUDE.md at pre-flight and passes a condensed project context to agents — agents should not read CLAUDE.md themselves unless they need additional detail from subdirectory CLAUDE.md files.
- The pr-review-toolkit agents (code-reviewer, silent-failure-hunter, etc.) are reused as-is.
- GitHub write operations use `gh` CLI. GitHub read operations may use either `gh` or the GitHub MCP tools.
- Findings are posted to GitHub only in two cases: (1) own PR with `--post-findings`, using a `COMMENT`-type review; (2) external PR via `--pr`, using `REQUEST_CHANGES` if Medium+ findings exist or `COMMENT` if only Low. When creating a new PR, findings are always local — the author should fix them before others see the PR. Use `--no-post` to suppress all GitHub operations.
- Inline comments are capped at 25 per review (top findings by severity). Overflow goes to the review body. This prevents GitHub API throttling on large finding sets.
- `--pr` mode creates a temporary worktree and checks out the PR branch. The worktree is removed in Phase 5. If the skill is interrupted, clean up manually with `git worktree list` and `git worktree remove`.
