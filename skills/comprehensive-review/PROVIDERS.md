# Provider Operations Reference

> This file is read on demand by the orchestrator in Phase 4 and Phase 4b when remote
> posting operations are needed. Skip reading it in `--no-post`/`--local` mode.

The following operations are referenced by name throughout Phases 4 and 4b. Use the
command corresponding to the detected PROVIDER.

## OP: Fetch PR/MR metadata (returns JSON with number, title, base branch, head branch, state)

- **github:** `gh pr view <N> --json number,title,baseRefName,headRefName,state`
- **gitlab:** `glab mr view <N> --output json` (fields: iid, title, source_branch, target_branch, state). Map: iid→number, target_branch→baseRefName, source_branch→headRefName. State values: "opened"→OPEN, "closed"→CLOSED, "merged"→MERGED. If state is unrecognized, warn "Unrecognized MR state '<value>' — proceeding as OPEN." and treat as OPEN.
- **bitbucket:** `curl -sf -H "Authorization: Bearer $BITBUCKET_TOKEN" "https://api.bitbucket.org/2.0/repositories/${REPO_SLUG}/pullrequests/<N>"`. Map: id→number, destination.branch.name→baseRefName, source.branch.name→headRefName. State values: "OPEN", "DECLINED"→CLOSED, "MERGED".

## OP: Checkout PR/MR branch into current worktree

- **github:** `gh pr checkout <N>`
- **gitlab:** `glab mr checkout <N>`
- **bitbucket:** Extract source branch name from PR metadata, then `git fetch origin <branch> && git checkout FETCH_HEAD`

## OP: Detect existing PR/MR on current branch (returns metadata or fails)

- **github:** `gh pr view --json number,title,body`
- **gitlab:** `glab mr list --source-branch "$(git branch --show-current)" --output json` (returns `[]` when no MR exists)
- **bitbucket:** `curl -sf -H "Authorization: Bearer $BITBUCKET_TOKEN" "https://api.bitbucket.org/2.0/repositories/${REPO_SLUG}/pullrequests?q=source.branch.name=\"$(git branch --show-current)\"&state=OPEN"`. If `curl` exits non-zero or the response contains `"type":"error"`, treat as API failure (not "no PR found"). Otherwise check `.size > 0`; if so, first result is the PR.

## OP: Create PR/MR

- **github:** `gh pr create --title "<title>" --base "<base>" --body "<body>"`
- **gitlab:** `glab mr create --title "<title>" --target-branch "<base>" --description "<body>" --no-editor`
- **bitbucket:** `curl -sf -X POST -H "Authorization: Bearer $BITBUCKET_TOKEN" -H "Content-Type: application/json" "https://api.bitbucket.org/2.0/repositories/${REPO_SLUG}/pullrequests" -d '{"title":"<title>","source":{"branch":{"name":"<head>"}},"destination":{"branch":{"name":"<base>"}},"description":"<body>"}'`

## OP: Post comment on PR/MR

- **github:** `gh pr comment <N> --body "<body>"`
- **gitlab:** `glab mr comment <N> --message "<body>"`
- **bitbucket:** `curl -sf -X POST -H "Authorization: Bearer $BITBUCKET_TOKEN" -H "Content-Type: application/json" "https://api.bitbucket.org/2.0/repositories/${REPO_SLUG}/pullrequests/<N>/comments" -d '{"content":{"raw":"<body>"}}'`

## OP: Post inline review (Phase 4b only)

- **github:** `mcp__github-pat__create_pull_request_review` (owner, repo, pull_number, event, body, comments). Fallback: `gh api`. Supports REQUEST_CHANGES and COMMENT events.
- **gitlab:** Create a review via Draft Notes API or post individual discussion threads:
  For each inline comment (shell-escape all interpolated values — body, file path, line — to prevent injection via crafted filenames or review content): `glab api -X POST "projects/${PROJECT_ID}/merge_requests/<N>/discussions" -f "body=<body>" -f "position[base_sha]=<base_sha>" -f "position[head_sha]=<head_sha>" -f "position[start_sha]=<start_sha>" -f "position[position_type]=text" -f "position[new_path]=<file>" -f "position[new_line]=<line>"`.
  For the review body: `glab mr comment <N> --message "<review body>"`.
  GitLab does not have a single-call "submit review with inline comments" API like GitHub. Inline comments are posted as discussion threads. There is no REQUEST_CHANGES event — use an "unapprove" or simply post as comments.
- **bitbucket:** NOT SUPPORTED for inline diff comments. Post Block B as a single PR comment instead (using OP: Post comment). Note in terminal output: "Note: Inline review comments are not supported on Bitbucket. Findings posted as a PR comment."
