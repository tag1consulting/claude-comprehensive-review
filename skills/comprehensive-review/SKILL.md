---
name: comprehensive-review
description: >
  Run a comprehensive CodeRabbit-style PR review using specialized agents.
  Produces a structured PR summary and a findings report. Supports reviewing
  your own branch (pre-PR) or an existing PR by number (--pr <N>).

  Default behavior:
    No PR exists:      Everything shown locally. Use --create-pr to create a PR.
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
- `--quick` — fast mode: pr-summarizer + code-reviewer + triggered error/test agents only; skips security, architecture, blind-hunter, edge-case-hunter, comment, and type analysis (~75% cheaper)
- `--diagrams` — include Mermaid sequence diagrams in Block A (default: omitted; always omitted in `--quick`)
- `--security-only` — run security-reviewer only
- `--summary-only` — run pr-summarizer only
- `--create-pr` — create a PR using Block A as the description (without this flag, no PR is created)
- `--post-summary` — post Block A (informational summary) as a comment on an existing PR
- `--post-findings` — post Block B (findings) as inline GitHub review on an existing own PR
- `--no-findings` — suppress posting findings as a review (useful for dry-run with `--pr`)
- `--no-post` / `--local` — display everything locally, skip all GitHub operations
- `--pr <number>` — review an existing PR by number (external review mode)
- `--help` — show this usage

## Pre-flight Context

- **Repository:** !`git remote get-url origin 2>/dev/null | sed 's|.*[:/]\([^:/]*\/[^:/]*\)\.git$|\1|; s|.*[:/]\([^:/]*\/[^:/]*\)$|\1|'`
- **Branch:** !`git branch --show-current 2>/dev/null`
- **Branch context:** !`BASE=$(git rev-parse --abbrev-ref HEAD@{upstream} 2>/dev/null | sed 's|origin/||' || echo "main"); echo "--- Upstream base: $BASE"; echo "--- Changed files:"; git diff --name-only "$BASE...HEAD" 2>/dev/null | head -40; echo "--- Diff stats:"; git diff --stat "$BASE...HEAD" 2>/dev/null | tail -3; echo "--- Commit log:"; git log --oneline "$BASE...HEAD" 2>/dev/null | head -20`

## Review Workflow

### Provider Detection

Detect the git hosting provider from the remote URL. This determines which CLI tool and API to use for all PR/MR operations.

1. Extract the remote URL: `git remote get-url origin 2>/dev/null`
2. If `--provider <name>` was passed, use that (valid values: `github`, `gitlab`, `bitbucket`). Skip auto-detection.
3. Otherwise, auto-detect:
   a. URL contains `github.com` → PROVIDER=github
   b. URL contains `gitlab.com` → PROVIDER=gitlab
   c. URL contains `bitbucket.org` → PROVIDER=bitbucket
   d. None of the above (possible self-hosted instance):
      - Run `gh auth status 2>&1`. If it succeeds OR mentions the remote's hostname → PROVIDER=github (GitHub Enterprise)
      - Otherwise, run `glab auth status 2>&1`. If it succeeds OR mentions the remote's hostname → PROVIDER=gitlab (self-hosted GitLab)
      - Otherwise: report "Could not detect git provider from remote URL '<url>'. Use --provider github|gitlab|bitbucket to specify." and stop.

4. Set provider-derived variables:
   - PROVIDER: github | gitlab | bitbucket
   - PR_TERM: "PR" (github, bitbucket) or "MR" (gitlab)
   - PR_TERM_LONG: "pull request" (github, bitbucket) or "merge request" (gitlab)
   - CLI_TOOL: "gh" (github) or "glab" (gitlab) or "curl" (bitbucket)

5. Validate CLI tool availability:
   - GitHub: `gh --version` must succeed. If not: "Error: gh CLI is required for GitHub repositories. Install: https://cli.github.com/"
   - GitLab: `glab --version` must succeed. If not: "Error: glab CLI is required for GitLab repositories. Install: https://gitlab.com/gitlab-org/cli"
   - Bitbucket: `curl --version` must succeed (should always be available). Also verify BITBUCKET_TOKEN or BITBUCKET_APP_PASSWORD env var is set: "Error: BITBUCKET_TOKEN or BITBUCKET_APP_PASSWORD environment variable is required for Bitbucket repositories."

Note: The `mcp__github-pat__*` tools in the `allowed-tools` frontmatter are only used when PROVIDER=github. For other providers, all operations use CLI tools (glab, curl) via Bash.

### Provider Operations Reference

The following operations are referenced by name throughout Phases 0, 4, and 4b. Use the command corresponding to the detected PROVIDER.

#### OP: Fetch PR/MR metadata (returns JSON with number, title, base branch, head branch, state)

- **github:** `gh pr view <N> --json number,title,baseRefName,headRefName,state`
- **gitlab:** `glab mr view <N> --output json` (fields: iid, title, source_branch, target_branch, state). Map: iid→number, target_branch→baseRefName, source_branch→headRefName. State values: "opened"→OPEN, "closed"→CLOSED, "merged"→MERGED.
- **bitbucket:** `curl -s -H "Authorization: Bearer $BITBUCKET_TOKEN" "https://api.bitbucket.org/2.0/repositories/${REPO_SLUG}/pullrequests/<N>"`. Map: id→number, destination.branch.name→baseRefName, source.branch.name→headRefName. State values: "OPEN", "DECLINED"→CLOSED, "MERGED".

#### OP: Checkout PR/MR branch into current worktree

- **github:** `gh pr checkout <N>`
- **gitlab:** `glab mr checkout <N>`
- **bitbucket:** Extract source branch name from PR metadata, then `git fetch origin <branch> && git checkout FETCH_HEAD`

#### OP: Detect existing PR/MR on current branch (returns metadata or fails)

- **github:** `gh pr view --json number,title,body`
- **gitlab:** `glab mr view --output json` (uses current branch)
- **bitbucket:** `curl -s -H "Authorization: Bearer $BITBUCKET_TOKEN" "https://api.bitbucket.org/2.0/repositories/${REPO_SLUG}/pullrequests?q=source.branch.name=\"$(git branch --show-current)\"&state=OPEN"`. Check `.size > 0`; if so, first result is the PR.

#### OP: Create PR/MR

- **github:** `gh pr create --title "<title>" --base "<base>" --body "<body>"`
- **gitlab:** `glab mr create --title "<title>" --target-branch "<base>" --description "<body>" --no-editor`
- **bitbucket:** `curl -s -X POST -H "Authorization: Bearer $BITBUCKET_TOKEN" -H "Content-Type: application/json" "https://api.bitbucket.org/2.0/repositories/${REPO_SLUG}/pullrequests" -d '{"title":"<title>","source":{"branch":{"name":"<head>"}},"destination":{"branch":{"name":"<base>"}},"description":"<body>"}'`

#### OP: Post comment on PR/MR

- **github:** `gh pr comment <N> --body "<body>"`
- **gitlab:** `glab mr comment <N> --message "<body>"`
- **bitbucket:** `curl -s -X POST -H "Authorization: Bearer $BITBUCKET_TOKEN" -H "Content-Type: application/json" "https://api.bitbucket.org/2.0/repositories/${REPO_SLUG}/pullrequests/<N>/comments" -d '{"content":{"raw":"<body>"}}'`

#### OP: Post inline review (Phase 4b only)

- **github:** `mcp__github-pat__create_pull_request_review` (owner, repo, pull_number, event, body, comments). Fallback: `gh api`. Supports REQUEST_CHANGES and COMMENT events.
- **gitlab:** Create a review via Draft Notes API or post individual discussion threads:
  For each inline comment: `glab api -X POST "projects/${PROJECT_ID}/merge_requests/<N>/discussions" -f "body=<body>" -f "position[base_sha]=<base_sha>" -f "position[head_sha]=<head_sha>" -f "position[start_sha]=<start_sha>" -f "position[position_type]=text" -f "position[new_path]=<file>" -f "position[new_line]=<line>"`.
  For the review body: `glab mr comment <N> --message "<review body>"`.
  GitLab does not have a single-call "submit review with inline comments" API like GitHub. Inline comments are posted as discussion threads. There is no REQUEST_CHANGES event — use an "unapprove" or simply post as comments.
- **bitbucket:** NOT SUPPORTED for inline diff comments. Post Block B as a single PR comment instead (using OP: Post comment). Note in terminal output: "Note: Inline review comments are not supported on Bitbucket. Findings posted as a PR comment."

### Phase 0: Pre-flight and Manifest Construction

1. Parse `$ARGUMENTS`:
   - If `--help` is present, display the help text below and **stop immediately** — do not continue.
   - Extract `--base <branch>` if present, otherwise use the detected upstream base, falling back to `main`
   - Extract `--pr <number>` if present — set PR_NUMBER and enable external review mode
   - Extract `--provider <name>` if present — passed to Provider Detection (valid: `github`, `gitlab`, `bitbucket`)
   - Note mode flags: `--quick`, `--diagrams`, `--security-only`, `--summary-only`, `--create-pr`,
     `--no-post`/`--local`, `--post-summary`, `--post-findings`, `--no-findings`
   - **Flag conflict checks:**
     - If both `--post-findings` and `--no-findings` are present, report
       "Error: --post-findings and --no-findings are mutually exclusive." and stop.
     - If `--create-pr` and `--no-post`/`--local` are both present, report
       "Error: --create-pr and --no-post/--local are mutually exclusive." and stop.
     - If `--create-pr` and `--pr <N>` are both present, report
       "Error: --create-pr and --pr are mutually exclusive." and stop.

**Help text:** Read and display `skills/comprehensive-review/HELP.md`, then stop. If the file is not found, display: "Help file not found. Run `/plugins install comprehensive-review@tag1consulting` to reinstall."

2. **If `--pr <N>` was passed** (external review mode):
   a. Fetch PR/MR metadata using **OP: Fetch PR/MR metadata**. Map provider-specific fields to canonical names (number, title, baseRefName, headRefName, state).
   b. If state is CLOSED or MERGED (after provider-specific mapping), report "Error: ${PR_TERM} #<N> is <state>." and stop.
   c. Set BASE to baseRefName (mapped).
   d. Create a temporary worktree: `WORKTREE_PATH=$(mktemp -d /tmp/cr-pr-XXXXXXXX)`, then
      `rmdir "$WORKTREE_PATH" && git worktree add "$WORKTREE_PATH" --detach` and
      checkout using **OP: Checkout PR/MR branch** (run from inside `$WORKTREE_PATH`). On checkout failure:
      run `git worktree remove "$WORKTREE_PATH" --force 2>/dev/null`, report error, and stop.
      Track WORKTREE_PATH for Phase 5 cleanup.
   e. All subsequent git commands must use `git -C "$WORKTREE_PATH"` in `--pr` mode.

3. Run `git diff --name-only <base>...HEAD` to confirm changed files (in `--pr` mode: `git -C "$WORKTREE_PATH" diff --name-only <base>...HEAD`). If none, report and stop.

4. **Build the file manifest** from `git diff --stat <base>...HEAD -- ':!*lock.json' ':!*lock.yaml' ':!vendor/*' ':!*.sum' ':!node_modules/*'`:
   Lockfiles, vendor directories, and checksum files are excluded — the full DIFF_FILE still includes them.
   - Detect languages from extensions; categorize files as **Source**, **Tests**, **Config**, **Docs**, or **Dependency**
   - Format:
     ```
     BASE: <base>  |  LANGUAGES: Go, TypeScript  |  FILES: <N>  |  LINES: +<added>/-<removed>

     Source:  path/to/file.go (+45/-12), path/to/other.go (+30/-5), ...
     Tests:   path/to/file_test.go (+20/-0)
     Config:  .github/workflows/ci.yml (+5/-2)
     Deps:    go.mod (+2/-1)
     Docs:    README.md (+10/-3)
     ```
     Omit empty categories. Binary/generated files go under **Other**.

5. **Read project context** — if CLAUDE.md exists in the repo root, extract a condensed
   project-context block (~500 tokens max). Also check subdirectories of changed files.
   If none exists: "No project-specific context available."

6. **Capture the commit log** — `git log --oneline <base>...HEAD` (already available from
   pre-flight for own-branch; captured fresh for `--pr` mode). Passed to agents so they
   don't fetch independently.

7. **Determine diff size tier** from the manifest's total changed lines (lockfiles excluded):
   - **Small** (under 300 lines): full diff passed inline to agents
   - **Medium/Large** (300+ lines): agents receive file manifest and read selectively
   - Default to **Medium/Large** if line count is ambiguous

8. Determine which agents to run (see Phase 1).

### Phase 1: Launch Agents in Parallel

#### Context Passing

**Do not display raw diffs to the user.** Write diffs to temp files via `mktemp /tmp/cr-diff-XXXXXXXX.txt`, then Read them. Track all temp files for Phase 5 cleanup.

**Small diffs (under 300 lines):** Capture full diff once to a temp file. Pass inline to all agents.

**Medium/large diffs (300+ lines):** Pass each agent: file manifest, base branch name, condensed project context, and commit log (where needed). Custom agents read files selectively via `git diff <base>...HEAD -- <file>`.

**pr-review-toolkit agents** (cannot modify) receive **relevant diff slices**:
- **code-reviewer** — full diff
- **silent-failure-hunter** — only files with error-handling patterns
- **pr-test-analyzer** — only test files and source counterparts
- **comment-analyzer** — only files with comment changes
- **type-design-analyzer** — only files with type/struct/interface definitions

Produce slices via `mktemp /tmp/cr-slice-<agent>-XXXXXXXX.txt` and `git diff <base>...HEAD -- <files>`. Skip agents with empty slices.

#### Agent Roster

**Mode flag effects:**

| Flag | Agents that run |
|------|-----------------|
| (none) | All always-run + all triggered conditional agents (no diagrams unless `--diagrams` passed) |
| `--quick` | pr-summarizer (no diagrams) + code-reviewer + triggered silent-failure-hunter and pr-test-analyzer |
| `--security-only` | security-reviewer only |
| `--summary-only` | pr-summarizer only |

**Model assignments** — always specify `model:` explicitly when spawning agents via the Agent tool to prevent inheritance of the orchestrator's model:

| Agent | Model |
|-------|-------|
| pr-summarizer | sonnet |
| code-reviewer | sonnet |
| architecture-reviewer | opus |
| security-reviewer | opus |
| blind-hunter | sonnet |
| edge-case-hunter | sonnet |
| silent-failure-hunter | sonnet |
| pr-test-analyzer | sonnet |
| comment-analyzer | sonnet |
| type-design-analyzer | sonnet |
| issue-linker | haiku |

**Always-run agents** (unless `--security-only` or `--summary-only` limits scope):

- **pr-summarizer** (model: sonnet) — pass manifest, commit log, project context. Small diffs: also full diff inline.
  Unless `--diagrams` is passed (and not `--quick`): add "Omit the Sequence Diagrams section entirely."
- **code-reviewer** (pr-review-toolkit, model: sonnet) — always pass the full diff.

**Full-run-only agents** (skipped with `--quick`):

- **architecture-reviewer** (model: opus) — pass manifest, commit log, project context. Small diffs: also full diff inline.
- **security-reviewer** (model: opus) — pass manifest, commit log, detected languages, project context. Small diffs: also full diff inline.
- **blind-hunter** (model: sonnet) — **ZERO CONTEXT CONSTRAINT: pass ONLY the diff. No manifest, no project context, no commit log.**
  Small diffs: full diff inline only.
  Medium/large (non-`--pr`): base branch name + plain file list from `git diff --name-only` (NOT the categorized manifest). Agent reads files via `git diff <base>...HEAD -- <file>`.
  Medium/large (`--pr` mode): `git -C "$WORKTREE_PATH" diff <base>...HEAD > /tmp/cr-diff-blind.txt`, passes inline (agent has no worktree knowledge).
- **edge-case-hunter** (model: sonnet) — pass manifest, commit log, project context. Small diffs: also full diff inline.
  Has full codebase read access for surrounding context.

**Conditional agents — run in both full and `--quick` when triggered:**

Detect triggers via grep on the temp diff file — do NOT read it into the conversation:
```bash
grep -l 'catch\|if err\|try {\|rescue\|Result<\|unwrap\|\.error\|\.expect(\|?\|runCatching\|guard\|throws' "$DIFF_FILE"
```

- **silent-failure-hunter** (pr-review-toolkit, model: sonnet) — trigger: error handling patterns (`catch`, `if err`, `try {`, `rescue`, `Result<`, `unwrap`, etc.). Pass only matching files' diff.
- **pr-test-analyzer** (pr-review-toolkit, model: sonnet) — trigger: test files (`*_test.go`, `test_*.py`, `*.test.ts`, `*.spec.ts`, `spec/`, `__tests__/`). Pass test files + source counterparts.

**Conditional agents — full-run only** (skip in `--quick` and when not triggered):

- **comment-analyzer** (pr-review-toolkit, model: sonnet) — trigger: comment lines (`//`, `#`, `/*`, `"""`, `'''`). Pass matching files' diff.
- **type-design-analyzer** (pr-review-toolkit, model: sonnet) — trigger: type definitions (`type ... struct`, `interface `, `class `, `enum `). Pass matching files' diff.
- **issue-linker** (model: haiku) — pass commit log, branch name, manifest, repo slug. Skip in `--quick` and `--pr` modes.

Track skipped agents and reasons for Phase 5. Launch all applicable agents simultaneously.

### Phase 2: Collect and Normalize Results

Wait for all agents. Check each output:
- Exactly `NONE` (trimmed) → mark as clean (no findings). Omit from Block B. Not an error.
- Empty or missing expected headers (and not NONE) → "WARNING: <agent> returned no results."
- Tool error/timeout → "ERROR: <agent> failed. Reason: <error>."
- Track failures for Phase 5.

**Severity normalization** (inclusive ranges):

| Agent | Their Scale | Maps To |
|-------|-------------|---------|
| code-reviewer | confidence [91,100] / [80,90] / [0,79] | Critical / High / Medium |
| silent-failure-hunter | CRITICAL/HIGH/MEDIUM | pass through |
| comment-analyzer | Critical/High/Medium/Low | pass through |
| pr-test-analyzer | gap [8,10] / [5,7] / [3,4] / [1,2] | Critical / High / Medium / Low |
| type-design-analyzer | rating [1,2] / [3,5] / [6,10] | High / Medium / Low |
| architecture-reviewer, security-reviewer | Critical/High/Medium | pass through (Medium+ only) |
| blind-hunter, edge-case-hunter | Critical/High/Medium/Low | pass through |

**Deduplicate:** same `file:line` from two agents → keep highest severity, note "(also flagged by [agent2])". Same file without line → deduplicate by file + category.

**Collect as structured data:** `{ severity, agent, file, line, finding, remediation }` per finding. Used for Block B rendering and Phase 4b inline comments.

### Phase 3: Assemble the Reports

Build two separate output blocks:

#### Block A — Informational (conditionally posted to GitHub)

Assemble the pr-summarizer and issue-linker outputs into this format.
**Omit the `## Sequence Diagrams` section unless `--diagrams` was passed** (pr-summarizer was told not to generate it).
If issue-linker returned NONE or was skipped, omit the `## Related Issues & PRs` section entirely.

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

<from pr-summarizer — include only if --diagrams was passed and not --quick>

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

<condensed output from architecture-reviewer, or omit if skipped or NONE>

### Security Analysis

<condensed output from security-reviewer, or omit if skipped or NONE>

### Positive Observations

<aggregated from all agents>

### Recommended Actions

1. <prioritized list of what to fix before the PR goes out for review>
2. ...

---
```

### Phase 4: PR/MR Operations

**Skip entirely if `--no-post` or `--local` was passed.**

Determine PR/MR state:
- `--pr` mode: PR_NUMBER from arg. POST_SUMMARY = `--post-summary`. POST_FINDINGS = NOT `--no-findings`.
- Own-branch: use **OP: Detect existing PR/MR on current branch**.
  - Fails with "no ${PR_TERM_LONG}s found": no PR/MR exists.
    + `--create-pr`: create PR/MR. POST_FINDINGS = `--post-findings` was passed.
    + No `--create-pr`: posting flags are no-ops (warn user if passed).
  - Fails for other reasons (auth, network): report "${PROVIDER} API error: <error>. Use --no-post to skip remote operations." and skip Phase 4.
  - Succeeds: PR_NUMBER from output. POST_SUMMARY/POST_FINDINGS from flags. If `--create-pr` also passed, note PR/MR already exists.

**Create PR/MR** (own-branch, `--create-pr`): Use **OP: Create PR/MR** with title (under 70 chars), base branch, and Block A as body.

**Post summary comment** (POST_SUMMARY): Use **OP: Post comment on PR/MR** with Block A as body. Use `## ${PR_TERM} Review Summary (Updated)` heading if summary already exists.

### Phase 4b: Post Findings as Inline Review

**Skip if POST_FINDINGS is false or `--no-post`/`--local` was passed.**

1. **Parse valid comment targets** from DIFF_FILE. For each hunk `@@ -a,b +c,d @@`, lines `c` through `c+d-1` are valid. Build lookup: `{file → set of valid lines}`.

2. **Partition findings:** INLINE (file + line both set and line is in valid set) vs BODY (everything else).

3. **Cap at 25 inline comments** sorted by severity. Overflow moves to BODY.

4. **Review event:**
   - **GitHub:** Own PR → "COMMENT". External PR (`--pr`) → "REQUEST_CHANGES" if Medium+ findings, "COMMENT" if Low only.
   - **GitLab:** Always post as discussion comments (GitLab has no review event model). Severity noted in comment text.
   - **Bitbucket:** Inline reviews not supported. Post Block B as a single PR comment using **OP: Post comment on PR/MR**. Skip steps 5–7.

5. **Review body:**
   ```markdown
   ## Comprehensive Review Findings

   **Overall Risk:** <severity>
   **Review mode:** <--quick if applicable, else full>
   **Agents:** <comma-separated list>

   ### Findings not attached to specific lines
   <BODY findings, or "None — all findings are attached inline.">
   ```

6. **Comments array:** each entry `{ "path", "line", "body": "**[Severity]** **[agent]** description.\n\n**Remediation:** ..." }`

7. **Submit** using **OP: Post inline review**:
   - GitHub: via `mcp__github-pat__create_pull_request_review` (owner, repo, pull_number, event, body, comments). Fall back to `gh api` if MCP fails.
   - GitLab: post review body as MR comment, then post each inline comment as a discussion thread via `glab api`.
   - Bitbucket: post entire Block B as a single PR comment (inline not supported).

8. Report for Phase 5: "Review posted to ${PR_TERM} #<N>: <N> inline, <M> in body"
   Bitbucket variant: "Findings posted as comment on ${PR_TERM} #<N> (inline reviews not supported on Bitbucket)"

### Phase 5: Final Output

**Cleanup:** `rm -f` all temp diff/slice files. If `--pr` mode: `git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || true`.

**Display in terminal:**
1. PR/MR created → "${PR_TERM} created: <URL>". No PR/MR + no `--create-pr` → "Tip: use --create-pr to create a ${PR_TERM_LONG}."
2. Summary posted → "Summary comment posted to ${PR_TERM} #<N>"
3. Review posted → "Review posted to ${PR_TERM} #<N>: <N> inline, <M> in body"
4. Always display Block B (findings).
5. Report skipped agents: "--quick mode skipped: ..." and "Skipped (no patterns): ..."
6. Critical/High findings → "⚠ Address Critical/High findings before requesting review."
7. Agent failures → "⚠ Review incomplete — <N> agent(s) failed."
8. No findings + no failures → "No significant issues found. Ready for review."

## Notes

- Project-agnostic. Orchestrator reads CLAUDE.md at pre-flight and passes condensed context; agents should not read CLAUDE.md independently.
- pr-review-toolkit agents are reused as-is. Remote writes use the provider-specific CLI (gh/glab/curl); reads may use CLI or MCP tools (GitHub only).
- `--create-pr` is opt-in. Default is side-effect-free (no PR/MR created, no remote posts).
- Findings posted to the hosting provider only via `--post-findings` (own PR/MR, GitHub/GitLab: inline review; Bitbucket: PR comment) or `--pr` mode (GitHub: `REQUEST_CHANGES` if Medium+, `COMMENT` if Low only; GitLab: discussion threads; Bitbucket: PR comment). `--create-pr` findings are local unless `--post-findings` also passed.
- Inline comments capped at 25 per review (top findings by severity); overflow goes to review body.
- If `--pr` mode is interrupted, clean up with `git worktree list` and `git worktree remove`.
