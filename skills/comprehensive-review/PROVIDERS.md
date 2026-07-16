# Provider Operations Reference

> This file is read on demand by the orchestrator in Phase 4 and Phase 4b when remote
> posting operations are needed. Skip reading it in `--no-post`/`--local` mode.

The following operations are referenced by name throughout Phases 4 and 4b. Use the
command corresponding to the detected PROVIDER.

## OP: Fetch PR/MR metadata (returns JSON with number, title, base branch, head branch, state, body)

- **github:** `gh pr view <N> --json number,title,baseRefName,headRefName,state,body`. Map `body` to canonical `body`.
- **gitlab:** `glab mr view <N> --output json` (fields: iid, title, source_branch, target_branch, state, description). Map: iid→number, target_branch→baseRefName, source_branch→headRefName, description→body. State values: "opened"→OPEN, "closed"→CLOSED, "merged"→MERGED. If state is unrecognized, warn "Unrecognized MR state '<value>' — proceeding as OPEN." and treat as OPEN.
- **bitbucket:** `curl -sf --user "${BITBUCKET_EMAIL}:${BITBUCKET_TOKEN}" "https://api.bitbucket.org/2.0/repositories/${REPO_SLUG}/pullrequests/<N>"`. Map: id→number, destination.branch.name→baseRefName, source.branch.name→headRefName, description→body. State values: "OPEN", "DECLINED"→CLOSED, "MERGED".

If the provider response does not include a body/description field or the value is null/empty, set `body=""` (empty string). Do not error.

## OP: Checkout PR/MR branch into current worktree

- **github:** `gh pr checkout <N>`
- **gitlab:** `glab mr checkout <N>`
- **bitbucket:** Extract source branch name from PR metadata, then `git fetch origin <branch> && git checkout FETCH_HEAD`

## OP: Detect existing PR/MR on current branch (returns metadata or fails)

- **github:** `gh pr view --json number,title,body`
- **gitlab:** `glab mr list --source-branch "$(git branch --show-current)" --output json` (returns `[]` when no MR exists)
- **bitbucket:** `curl -sf --user "${BITBUCKET_EMAIL}:${BITBUCKET_TOKEN}" "https://api.bitbucket.org/2.0/repositories/${REPO_SLUG}/pullrequests?q=source.branch.name=\"$(git branch --show-current)\"&state=OPEN"`. If `curl` exits non-zero or the response contains `"type":"error"`, treat as API failure (not "no PR found"). Otherwise check `.size > 0`; if so, first result is the PR.

## Safe payload construction (mandatory)

Any time the orchestrator builds a JSON request body from values that originate
in attacker-influenceable content (PR title, PR/MR description body, finding
text, file paths, branch names, etc.), construct the JSON with `jq -n --arg`
and pass it via `--data-binary "$BODY"` (or the equivalent `--input` for
`gh api`). Never build a JSON request body by interpolating those values into
a string literal that is passed to `curl -d` or `gh api -f` — an unescaped
double-quote, backslash, or newline in any input field breaks out of the
template and clobbers sibling fields.

This is the same pattern SKILL.md mandates for the claude-mem save (search
SKILL.md for `jq -n --arg`). The OP templates below all follow it.

## OP: Create PR/MR

- **github:** `gh pr create --title "<title>" --base "<base>" --body "<body>"` (the `gh` CLI handles arg quoting; safe).
- **gitlab:** `glab mr create --title "<title>" --target-branch "<base>" --description "<body>" --no-editor` (the `glab` CLI handles arg quoting; safe).
- **bitbucket:** Build the body with `jq -n --arg` and post it via `--data-binary`:
  ```bash
  BODY=$(jq -n \
    --arg title  "<title>" \
    --arg head   "<head>" \
    --arg base   "<base>" \
    --arg desc   "<body>" \
    '{title: $title,
      source:      {branch: {name: $head}},
      destination: {branch: {name: $base}},
      description: $desc}')
  curl -sf -X POST \
    --user "${BITBUCKET_EMAIL}:${BITBUCKET_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary "$BODY" \
    "https://api.bitbucket.org/2.0/repositories/${REPO_SLUG}/pullrequests"
  ```

## OP: Post comment on PR/MR

- **github:** `gh pr comment <N> --body "<body>"` (the `gh` CLI handles arg quoting; safe).
- **gitlab:** `glab mr comment <N> --message "<body>"` (the `glab` CLI handles arg quoting; safe).
- **bitbucket:** Build the body with `jq -n --arg` and post it via `--data-binary`:
  ```bash
  BODY=$(jq -n --arg body "<body>" '{content: {raw: $body}}')
  curl -sf -X POST \
    --user "${BITBUCKET_EMAIL}:${BITBUCKET_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary "$BODY" \
    "https://api.bitbucket.org/2.0/repositories/${REPO_SLUG}/pullrequests/<N>/comments"
  ```

## OP: Post inline review (Phase 4b only)

- **github:** Build the comments array with `jq` from a finding-source file (one row per finding: file, line, comment), assemble the full review body with `jq -n --arg`/`--slurpfile`, and post via `gh api --input`. Choose `event` based on finding severity (`REQUEST_CHANGES` if any finding is Medium or higher; otherwise `COMMENT`). Owner and repo are extracted from the git remote URL.
  ```bash
  # findings.jsonl contains one JSON object per inline finding:
  #   {"path": "<file>", "line": <line>, "body": "<comment>"}
  # Built upstream via jq from the structured findings (never via string interpolation).
  touch findings.jsonl  # mandatory: do not skip -- ensures jq -s '.' always has a file to read
  COMMENTS=$(jq -s '.' findings.jsonl) || { echo 'ERROR: jq failed aggregating findings.jsonl'; exit 1; }
  echo "$COMMENTS" | jq -e 'if type == "array" then . else error("COMMENTS is not a JSON array") end' > /dev/null \
    || { echo 'ERROR: COMMENTS is not a JSON array after aggregation'; exit 1; }
  EVENT="REQUEST_CHANGES"               # or COMMENT, computed from severities
  REVIEW_BODY=$(jq -n \
    --arg event   "$EVENT" \
    --arg body    "<review body>" \
    --argjson cmts "$COMMENTS" \
    '{event: $event, body: $body, comments: $cmts}')
  echo "$REVIEW_BODY" | gh api --input - \
    "repos/{owner}/{repo}/pulls/{pull_number}/reviews"
  ```
- **gitlab:** Post each inline finding as an individual discussion thread using `glab api -f key=value` (the `-f` form URL-encodes each value; safe). Do not concatenate values into a single quoted string.
  ```bash
  # For each inline comment:
  glab api -X POST "projects/${PROJECT_ID}/merge_requests/<N>/discussions" \
    -f "body=<body>" \
    -f "position[base_sha]=<base_sha>" \
    -f "position[head_sha]=<head_sha>" \
    -f "position[start_sha]=<start_sha>" \
    -f "position[position_type]=text" \
    -f "position[new_path]=<file>" \
    -f "position[new_line]=<line>"
  # Review body posted as an MR comment (glab handles arg quoting):
  glab mr comment <N> --message "<review body>"
  ```
  GitLab has no single-call "submit review with inline comments" API like GitHub. There is no REQUEST_CHANGES event — use "unapprove" or post as comments.
- **bitbucket:** NOT SUPPORTED for inline diff comments. Post Block B as a single PR comment instead (using OP: Post comment). Note in terminal output: "Note: Inline review comments are not supported on Bitbucket. Findings posted as a PR comment."

## OP: Stage draft review (Phase 4b only — `POST_MODE=draft`, the default when `--post-findings` is passed without `--publish`)

This is the "Human in the Middle" staging path: the AI drafts, the human edits and submits. **This OP must never call a submit/publish endpoint.** It creates draft content under the invoking user's own credentials (gh/glab already authenticate as the user — see SKILL.md:77) and stops. The confirmation prompt that gates this OP (Phase 4b step 7) asks the user to authorize *staging*, not publishing.

**If draft mode misbehaves:** this OP depends on provider corner behavior (GitHub creating a PENDING, unsubmitted review when `event` is omitted; GitLab's `draft_notes` endpoint staying separate from published discussion threads) that is not under this project's control and could change. There is no automated detection if a provider changes this behavior out from under the tool. If you suspect a staged review published immediately, or findings appeared visible to others before you submitted: (1) check the review's state in the provider's web UI right after a run — GitHub shows a distinct "Pending" badge, GitLab shows draft notes under a separate "Your comment drafts" area; (2) if it published unexpectedly, treat it as a bug in this tool, not user error — report it (see the repo's issue tracker); (3) as an interim workaround, pass `--publish` for every run so behavior is deterministic and matches what you see immediately (today's pre-1.13.0 default), or pin to the last pre-1.13.0 release tag until the issue is resolved. There is no runtime self-check in this version that verifies a created review is genuinely PENDING before reporting success to the user — the Phase 5 status line cites the provider's returned identifier, not a re-fetched confirmation of draft state.

- **github:** Create a PENDING review by POSTing to the same endpoint as "OP: Post inline review" but with **`event` omitted entirely** — per GitHub's REST docs, leaving `event` blank sets the review to `PENDING` state, which is not submitted and does not notify or post anything until its author submits it themselves in the web UI. (GitHub's REST docs confirm the PENDING state and its not-yet-submitted behavior, but do not explicitly document an access-control/visibility guarantee for who can *see* a PENDING review before submission — this is widely relied on in practice, not a cited API contract. Treat "unpublished" as the verified property; "author-only visible" as a reasonable but unverified assumption.)
  ```bash
  # Same findings.jsonl -> COMMENTS construction as "OP: Post inline review".
  # The ONLY difference is the absence of an "event" key below.
  REVIEW_BODY=$(jq -n \
    --arg body    "<review body>" \
    --argjson cmts "$COMMENTS" \
    '{body: $body, comments: $cmts}')      # no "event" key -> PENDING, not published
  echo "$REVIEW_BODY" | gh api --input - \
    "repos/{owner}/{repo}/pulls/{pull_number}/reviews"
  ```
  **One pending review per PR per user:** GitHub returns 422 if the same user already has a PENDING review on this PR. Pre-check for an existing pending review before calling this (see SKILL.md Phase 4b step 0c) rather than relying on the 422 — a clear pre-check error is better than parsing a generic validation-failure response. Never resolve a 422 by submitting the existing pending review; that would publish content the human has not reviewed.
  Never follow this call with `POST .../reviews/{review_id}/events` (the review-submit endpoint) — that publishes the review. Draft mode has no submit step.
  **No append path (relevant to `--read-back`):** this REST endpoint only accepts `comments` at creation time — it cannot add comments to an *existing* pending review. Appending would require the GraphQL `addPullRequestReviewThread` mutation against the existing review's node ID, which this version does not implement. Consequence: `--read-back` on GitHub can report new findings in the terminal but cannot stage them into the existing draft (SKILL.md Read-Back Pass step 3 handles this by reporting only, not calling this OP a second time).
- **gitlab:** Post each inline finding as a **draft note** instead of an immediate discussion thread. Same `position[...]` fields as "OP: Post inline review", different endpoint and field name (`note`, not `body`):
  ```bash
  # For each inline comment:
  glab api -X POST "projects/${PROJECT_ID}/merge_requests/<N>/draft_notes" \
    -f "note=<body>" \
    -f "position[base_sha]=<base_sha>" \
    -f "position[head_sha]=<head_sha>" \
    -f "position[start_sha]=<start_sha>" \
    -f "position[position_type]=text" \
    -f "position[new_path]=<file>" \
    -f "position[new_line]=<line>"
  # Summary (Block A), if folded in: one additional draft note with no position[...] args:
  glab api -X POST "projects/${PROJECT_ID}/merge_requests/<N>/draft_notes" -f "note=<summary body>"
  ```
  Draft notes are "pending, unpublished comments … viewable only by the author until published" (GitLab Draft Notes API, Free tier — no license upgrade required). **Never call** `POST .../draft_notes/bulk_publish` — that is the human's action, done via the "Submit review" button in the MR UI. There is no per-note delete needed by this OP; the human manages their own drafts in the UI.
- **bitbucket:** **Not implemented.** The Bitbucket Cloud REST v2 comment schema has a `pending` boolean and the web UI's "Batched comments" feature ("Start review" / "Finish review") stages author-only comments, but creating a comment as pending via a public `POST .../pullrequests/{id}/comments` call is not confirmed in Atlassian's official REST documentation (that feature is documented as UI-driven). Building this without confirming the create path risks a call that silently publishes (if `pending` is ignored) or errors unpredictably. Until verified with a live API spike, `POST_MODE=draft` on Bitbucket falls back to the publish path (SKILL.md Phase 4b step 4a) with an explicit one-line notice — it does not attempt this OP.

**Managing your staged drafts:** drafts created by this OP persist until you submit or delete them yourself in the provider's web UI — this tool never does either. On GitHub, a forgotten pending review from a prior run silently blocks the next `--post-findings` invocation (the step 0c pre-check reports "you already have a pending review" and refuses to stage a second one); there is no `--discard-draft` flag or in-tool way to list/clear stale drafts in this version — go to the PR's "Files changed" tab and look for your own pending review, or check the PR's review list. On GitLab, orphaned `draft_notes` from an abandoned run accumulate under the MR's "Your comment drafts" area with no per-note cleanup path from this tool; they do not block future `--post-findings` runs the way GitHub's pending-review limit does, but they are equally easy to forget about.

**Known validation gap:** as of this OP's introduction (v1.13.0), GitHub draft staging and the `--read-back` flow were validated against a live PR (see the project's release history for the E2E test session). GitLab's draft-note staging and its `--read-back` net-new-finding staging path have **not** been exercised against a live MR — they are covered only by the structural bats tests in `tests/orchestration_contracts.bats`, which assert the correct API shape and the absence of publish-trigger calls, not that the calls succeed against a real GitLab instance. Treat the GitLab draft/read-back path as less battle-tested than GitHub's until a live GitLab E2E is run.
