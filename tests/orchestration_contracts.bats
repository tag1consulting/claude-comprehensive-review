#!/usr/bin/env bats
# Golden tests for orchestration decisions and structural contracts.
#
# Tests deterministic orchestration behavior:
#   - Tier selection based on diff size and file count
#   - Gate decisions for known fixture diffs
#   - Required SKILL.md sections still present
#   - json-findings schema fields documented in SEVERITY.md
#   - No remote operations documented as default
#
# These tests do NOT invoke LLM agents. They validate the deterministic
# scaffolding around the agents.

bats_require_minimum_version 1.5.0

setup() {
  load test_helper
  WORK=$(mktemp -d)
  SKILL_MD="${SCRIPTS_DIR}/../SKILL.md"
  SEVERITY_MD="${SCRIPTS_DIR}/../SEVERITY.md"
  PROVIDERS_MD="${SCRIPTS_DIR}/../PROVIDERS.md"
  HELP_MD="${SCRIPTS_DIR}/../HELP.md"
  README_MD="${SCRIPTS_DIR}/../../../README.md"
  CLAUDE_MD="${SCRIPTS_DIR}/../../../CLAUDE.md"
  GATE_SCRIPT="${SCRIPTS_DIR}/evaluate-gates.sh"
}

teardown() {
  rm -rf "$WORK"
}

# ---------------------------------------------------------------------------
# SKILL.md structural integrity
# ---------------------------------------------------------------------------

@test "SKILL.md: contains all required phase headings" {
  grep -q "### Phase 0" "$SKILL_MD"
  grep -q "### Phase 1:" "$SKILL_MD" || grep -q "### Phase 1b:" "$SKILL_MD"
  grep -q "### Phase 2" "$SKILL_MD"
  grep -q "### Phase 3" "$SKILL_MD"
  grep -q "### Phase 4" "$SKILL_MD"
  grep -q "### Phase 5" "$SKILL_MD"
}

@test "SKILL.md: defines TIER variable" {
  grep -q "TIER=" "$SKILL_MD"
}

@test "SKILL.md: defines tiny-tier threshold (50 lines, 3 files)" {
  grep -q "50" "$SKILL_MD"
  grep -q "TIER=tiny" "$SKILL_MD"
}

@test "SKILL.md: --quick flag is documented" {
  grep -q "\-\-quick" "$SKILL_MD"
}

@test "SKILL.md: --output-file references Write tool" {
  grep -q "Write tool\|via the Write" "$SKILL_MD"
}

@test "SKILL.md: no-post is described as the default" {
  grep -qi "no.post.*default\|default.*no.post\|no remote posting\|no-post is the default" "$SKILL_MD"
}

@test "SKILL.md: --create-pr from default branch is refused" {
  grep -q "default branch\|refused.*create-pr\|create-pr.*refused\|refused.*default" "$SKILL_MD"
}

@test "SKILL.md: Write tool is in allowed-tools frontmatter" {
  head -10 "$SKILL_MD" | grep -q '"Write"'
}

@test "SKILL.md: delegates gate evaluation to evaluate-gates.sh" {
  grep -q "evaluate-gates.sh" "$SKILL_MD"
}

@test "SKILL.md: defines DOCS_ONLY auto-cheap routing variable" {
  grep -q "DOCS_ONLY=true\|DOCS_ONLY=false" "$SKILL_MD"
}

@test "SKILL.md: defines LOW_RISK_CONFIG auto-cheap routing variable" {
  grep -q "LOW_RISK_CONFIG=true\|LOW_RISK_CONFIG=false" "$SKILL_MD"
}

@test "SKILL.md: Phase 5 reports DOCS_ONLY auto-cheap reason" {
  grep -q "Auto-cheap: DOCS_ONLY" "$SKILL_MD"
}

@test "SKILL.md: Phase 5 reports LOW_RISK_CONFIG auto-cheap reason" {
  grep -q "Auto-cheap: LOW_RISK_CONFIG" "$SKILL_MD"
}

@test "SKILL.md: novelty pass defined and only applies to Low/Medium findings" {
  grep -q "Novelty pass\|NOVELTY_DEMOTED_COUNT\|novelty candidate\|recurring" "$SKILL_MD"
  # Critical and High must be explicitly protected
  grep -q "never.*Critical.*High\|Critical.*High.*never" "$SKILL_MD"
}

@test "SKILL.md: novelty pass skipped when --no-mem or insufficient prior reviews" {
  grep -q "no-mem\|no.mem" "$SKILL_MD"
  grep -q "fewer than 2 prior review\|insufficient\|skip.*novelty" "$SKILL_MD"
}

# ---------------------------------------------------------------------------
# SEVERITY.md: json-findings contract documented
# ---------------------------------------------------------------------------

@test "SEVERITY.md: category field listed in json-findings contract" {
  grep -q "category" "$SEVERITY_MD"
}

@test "SEVERITY.md: all taxonomy values documented" {
  grep -q "authz" "$SEVERITY_MD"
  grep -q "injection" "$SEVERITY_MD"
  grep -q "dependency-cve" "$SEVERITY_MD"
  grep -q "secret" "$SEVERITY_MD"
  grep -q "architecture-coupling" "$SEVERITY_MD"
  grep -q "edge-case" "$SEVERITY_MD"
}

# ---------------------------------------------------------------------------
# PROVIDERS.md: correct GitHub inline review mechanism
# ---------------------------------------------------------------------------

@test "PROVIDERS.md: GitHub inline review uses gh api, not mcp tool" {
  grep -q "gh api" "$PROVIDERS_MD"
  if grep -q "mcp__github-pat__" "$PROVIDERS_MD"; then
    echo "REGRESSION: mcp__github-pat__ tool reference found in PROVIDERS.md" >&2
    return 1
  fi
}

@test "PROVIDERS.md: fetch PR/MR metadata includes body field for all providers" {
  grep -q "body" "$PROVIDERS_MD"
  # GitHub
  grep -q "gh pr view.*body\|--json.*body" "$PROVIDERS_MD"
  # GitLab maps description
  grep -q "description.*body\|description→body" "$PROVIDERS_MD"
  # Bitbucket
  grep -q "description.*body\|description→body" "$PROVIDERS_MD"
}

# ---------------------------------------------------------------------------
# PROVIDERS.md / SKILL.md: draft review mode ("Human in the Middle")
#
# The core invariant under test: draft mode STAGES and never PUBLISHES.
# These tests grep for the absence of publish-trigger strings inside the
# draft OP, not just the presence of draft-related strings, since a
# regression here (e.g. someone re-adding "event=" to the GitHub draft
# branch) would silently turn drafts back into immediate publishes.
# ---------------------------------------------------------------------------

@test "PROVIDERS.md: defines OP: Stage draft review" {
  grep -q "OP: Stage draft review" "$PROVIDERS_MD"
}

@test "PROVIDERS.md: Stage draft review OP documents a rollback story for provider API breakage" {
  # adversarial-general finding: no documented recovery path if GitHub/GitLab
  # change the provider behavior this OP depends on (event-omitted PENDING
  # review, draft_notes endpoint staying unpublished). The safety guarantee
  # the whole feature rests on needs a documented "what if it breaks" path.
  DRAFT_OP_BLOCK=$(awk '/## OP: Stage draft review/,0' "$PROVIDERS_MD")
  echo "$DRAFT_OP_BLOCK" | grep -qi "if draft mode misbehaves"
  echo "$DRAFT_OP_BLOCK" | grep -q -- "--publish"
}

@test "PROVIDERS.md: documents lifecycle guidance for stale/abandoned drafts" {
  # adversarial-general finding: a forgotten pending review silently blocks
  # the next --post-findings run on GitHub with no in-tool way to discover
  # or clear it, and no doc explains this can happen.
  DRAFT_OP_BLOCK=$(awk '/## OP: Stage draft review/,0' "$PROVIDERS_MD")
  echo "$DRAFT_OP_BLOCK" | grep -qi "managing your staged drafts"
}

@test "PROVIDERS.md: documents that GitLab draft/read-back staging is not live-E2E-validated" {
  # adversarial-general finding: GitLab's read-back write path is asserted
  # only by structural bats greps, never exercised end-to-end. This should
  # be visible to a maintainer/user, not silently assumed equivalent to the
  # GitHub path which was live-tested.
  DRAFT_OP_BLOCK=$(awk '/## OP: Stage draft review/,0' "$PROVIDERS_MD")
  echo "$DRAFT_OP_BLOCK" | grep -qi "known validation gap"
  echo "$DRAFT_OP_BLOCK" | grep -qi "not.*been exercised against a live MR\|not.*live-tested"
}

@test "PROVIDERS.md: GitHub PENDING-review visibility claim is not overstated as a documented API guarantee" {
  # Regression guard: security-reviewer found this file asserted "visible and
  # editable only by its author" as GitHub REST-documented behavior, but
  # GitHub's docs only confirm the PENDING/not-submitted state, not an
  # access-control guarantee for who can see a PENDING review. The entire
  # "Human in the Middle" design leans on this property, so overstating it
  # as verified is a real assurance gap if the property doesn't hold.
  GITHUB_DRAFT_BULLET=$(awk '/^- \*\*github:\*\* Create a PENDING review/,/^- \*\*gitlab:\*\*/' "$PROVIDERS_MD")
  echo "$GITHUB_DRAFT_BULLET" | grep -qi "not.*explicitly document\|unverified"
}

@test "PROVIDERS.md: GitHub draft path omits event and never calls the submit endpoint" {
  # Isolate the github bullet of the Stage draft review OP specifically (not
  # the whole OP section, which also contains gitlab/bitbucket bullets and
  # would let a gitlab-side false negative slip past this test).
  DRAFT_OP_BLOCK=$(awk '/## OP: Stage draft review/,0' "$PROVIDERS_MD")
  GITHUB_BULLET=$(echo "$DRAFT_OP_BLOCK" | awk '/\*\*github:\*\*/,/- \*\*gitlab:\*\*/')
  echo "$GITHUB_BULLET" | grep -q "gh api"
  echo "$GITHUB_BULLET" | grep -q "pulls/{pull_number}/reviews"
  # The draft OP's jq payload is a fenced ```bash block using "event: $event"
  # as an object KEY, never the "-f event=" gh-CLI-flag idiom (that idiom only
  # appears in the separate publish OP). Assert absence of BOTH forms inside
  # the actual jq-payload code fence, not just the -f flag form — a prior
  # version of this test checked only "-f event=" and verifiably passed even
  # with "event: $event" reintroduced into the payload, because that string
  # never appears in the -f form here.
  # NOTE: the range /```bash/,/```/ is a trap here — the opening fence line
  # ("```bash") itself matches the closing pattern ("```"), so awk closes the
  # range on the same line it opens and JQ_PAYLOAD ends up empty. Match the
  # opening/closing fence lines exactly instead.
  JQ_PAYLOAD=$(echo "$GITHUB_BULLET" | awk '/^  ```bash$/{p=1; next} p && /^  ```$/{p=0} p')
  if echo "$JQ_PAYLOAD" | grep -q -- '-f event='; then
    echo "REGRESSION: -f event= (gh CLI publish flag) found in GitHub draft jq payload" >&2
    return 1
  fi
  if echo "$JQ_PAYLOAD" | grep -Eq '\bevent\s*:\s*\$event\b'; then
    echo "REGRESSION: event: \$event key found in GitHub draft jq payload" >&2
    return 1
  fi
  if echo "$JQ_PAYLOAD" | grep -Eq -- '--arg event\b'; then
    echo "REGRESSION: --arg event found in GitHub draft jq payload" >&2
    return 1
  fi
  if echo "$DRAFT_OP_BLOCK" | grep -Eq '`[^`]*(gh api|curl)[^`]*reviews/\{review_id\}/events[^`]*`'; then
    echo "REGRESSION: draft OP references the reviews/{review_id}/events submit endpoint" >&2
    return 1
  fi
}

@test "PROVIDERS.md: GitLab draft path uses draft_notes and never calls bulk_publish" {
  # Same reasoning as the GitHub test above. The "never call bulk_publish"
  # warning is expected prose (and legitimately contains the string
  # "bulk_publish"), so a plain whole-block substring check would false-fail
  # on the warning itself. But the actual invocations in this file live in
  # fenced ```bash blocks, not inline backticks — a prior version of this
  # test required a single backtick pair around "bulk_publish", which does
  # not match a real invocation added inside a fenced block. Scope the
  # negative assertion to lines that look like actual API calls instead.
  DRAFT_OP_BLOCK=$(awk '/## OP: Stage draft review/,0' "$PROVIDERS_MD")
  GITLAB_BULLET=$(echo "$DRAFT_OP_BLOCK" | awk '/- \*\*gitlab:\*\*/,/- \*\*bitbucket:\*\*/')
  echo "$GITLAB_BULLET" | grep -q "draft_notes"
  if echo "$GITLAB_BULLET" | grep -E '^\s*(glab api|curl)' | grep -q "bulk_publish"; then
    echo "REGRESSION: GitLab draft path calls bulk_publish" >&2
    return 1
  fi
}

@test "PROVIDERS.md: Bitbucket draft support is explicitly not implemented" {
  DRAFT_OP_BLOCK=$(awk '/## OP: Stage draft review/,0' "$PROVIDERS_MD")
  echo "$DRAFT_OP_BLOCK" | grep -qi "not implemented\|not confirmed\|falls back to the publish path"
}

@test "SKILL.md: Orchestrator Governance states draft mode never publishes" {
  grep -qi "draft mode never publishes" "$SKILL_MD"
}

@test "SKILL.md: draft-never-publishes invariant documents that grep tests verify docs, not runtime behavior" {
  # architecture-reviewer finding: three of five commits on this branch are
  # fixes for the exact bug class (typo/degradation/logic error) that a
  # compiler or type system would catch at edit time in a real language.
  # This maintains the honesty of the safety claim by not letting a passing
  # bats suite be mistaken for a runtime guarantee.
  # Scope to the single governance bullet paragraph (from its bold lead-in to
  # the next top-level "- **" bullet) rather than a same-string range match,
  # since "no `--create-pr`" recurs later in the file and would over-capture.
  GOVERNANCE_BULLET=$(awk '/^- \*\*Draft mode never publishes\.\*\*/{p=1} p{print; if (/^- \*\*/ && !/^- \*\*Draft mode never publishes/) {if (++n>1) exit}}' "$SKILL_MD")
  echo "$GOVERNANCE_BULLET" | grep -qi "not a guarantee of runtime behavior"
}

@test "SKILL.md: --post-findings defaults to draft mode, --publish opts into publishing" {
  grep -q "\-\-publish" "$SKILL_MD"
  grep -q "\-\-draft" "$SKILL_MD"
  grep -qi "POST_MODE=draft" "$SKILL_MD"
}

@test "SKILL.md: --publish and --draft are documented as mutually exclusive" {
  grep -q "\-\-publish and --draft are mutually exclusive" "$SKILL_MD"
}

@test "SKILL.md: --read-back and --publish/--draft are documented as mutually exclusive" {
  grep -q "\-\-read-back and --publish are mutually exclusive" "$SKILL_MD"
  grep -q "\-\-read-back and --draft are mutually exclusive" "$SKILL_MD"
}

@test "SKILL.md: --read-back + --publish check appears before the --draft/--publish + --post-findings check (avoids contradictory-advice loop)" {
  # Regression guard: architecture-reviewer found that --read-back --publish
  # tripped the "--draft/--publish modify how --post-findings posts; pass
  # --post-findings" check first. Following that advice then trips the
  # --read-back + --post-findings exclusion two checks later -- a
  # contradictory-advice loop where fixing one error creates another. The
  # --read-back + --publish/--draft check must be ordered before the
  # --post-findings-requiring check so the correct, on-topic error fires first.
  READBACK_PUBLISH_LINE=$(grep -n "\-\-read-back and --publish are mutually exclusive" "$SKILL_MD" | head -1 | cut -d: -f1)
  POST_FINDINGS_REQUIRED_LINE=$(grep -n "modify how --post-findings posts; pass --post-findings" "$SKILL_MD" | head -1 | cut -d: -f1)
  [[ -n "$READBACK_PUBLISH_LINE" && -n "$POST_FINDINGS_REQUIRED_LINE" ]]
  [[ "$READBACK_PUBLISH_LINE" -lt "$POST_FINDINGS_REQUIRED_LINE" ]]
}

@test "SKILL.md: --read-back and --create-pr are documented as mutually exclusive" {
  grep -q "\-\-read-back and --create-pr are mutually exclusive" "$SKILL_MD"
}

@test "SKILL.md: GitHub pending-review one-per-PR pre-check is documented" {
  grep -qi "already have a pending review" "$SKILL_MD"
}

@test "SKILL.md: bare --post-findings without --publish/--draft emits a runtime migration notice" {
  # adversarial-general finding: the breaking-behavior-change note (pre-1.13.0
  # --post-findings published immediately; now stages) lives only in passive
  # docs. A returning CI script gets no distinct runtime signal that behavior
  # changed -- just a different outcome with no diagnostic.
  grep -qi "Migration notice for scripted/CI callers" "$SKILL_MD"
  grep -qi "as of v1.13.0, --post-findings stages a draft" "$SKILL_MD"
}

@test "SKILL.md: --read-back prints a cost notice before running the full pipeline" {
  # adversarial-general finding: --read-back re-runs the full analysis
  # pipeline ("costs the same as a full review") but nothing warns at
  # invocation time; a user reaching for a "just read my draft back" flag
  # would reasonably expect a cheap operation.
  grep -qi -- "read-back. cost notice" "$SKILL_MD"
  grep -qi "costs the same as a full review" "$SKILL_MD"
}

@test "SKILL.md: draft staging confirmation prompt does not use 'post' language" {
  grep -q "Stage this as your draft review" "$SKILL_MD"
}

@test "SKILL.md: step 0c pre-check skips (not falsely clears) EXISTING_PENDING when SELF_LOGIN fails" {
  # Regression guard: a prior version set SELF_LOGIN="" on lookup failure and then
  # queried select(.user.login=="") — an empty string can never match a real GitHub
  # login, so EXISTING_PENDING silently came back 0 even when a pending review
  # genuinely existed. The pre-check must skip the query entirely on lookup
  # failure, not run a query that is guaranteed to return a false "all clear".
  STEP0C_BLOCK=$(awk '/0c\. \*\*GitHub pending-review pre-check\*\*/,/^1\. \*\*Parse valid comment targets\*\*/' "$SKILL_MD")
  if echo "$STEP0C_BLOCK" | grep -q 'SELF_LOGIN=""$'; then
    echo "REGRESSION: SELF_LOGIN reset to empty string before the EXISTING_PENDING query (would silently match nothing)" >&2
    return 1
  fi
  echo "$STEP0C_BLOCK" | grep -q "EXISTING_PENDING=0"
  echo "$STEP0C_BLOCK" | grep -q "Skipping the pre-check"
}

@test "SKILL.md: read-back fetch-failure message does not suggest --no-post (mutually exclusive)" {
  # Regression guard: --read-back and --no-post/--local are mutually exclusive
  # (Phase 0 flag-conflict check), so telling the user to pass --no-post to
  # recover from a fetch failure sends them straight into a second, unrelated
  # error instead of resolving anything.
  READBACK_BLOCK=$(awk '/\*\*Read-Back Pass\*\*/,0' "$SKILL_MD")
  if echo "$READBACK_BLOCK" | grep -q "Use --no-post to skip"; then
    echo "REGRESSION: Read-Back Pass fetch-failure message suggests --no-post, which is mutually exclusive with --read-back" >&2
    return 1
  fi
}

@test "SKILL.md: --read-back is documented and requires an existing draft" {
  grep -q "\-\-read-back" "$SKILL_MD"
  grep -qi "no draft.*found\|requires an existing draft" "$SKILL_MD"
}

@test "SKILL.md: GitHub read-back resolves SELF_LOGIN before filtering PENDING reviews" {
  # Regression guard: the Read-Back Pass's GitHub PENDING-review filter needs the
  # invoking user's login, but Phase 4b step 0c (the only other SELF_LOGIN
  # resolution) is scoped to the staging path and does not run for --read-back.
  # A prior version of this spec used a literal, never-resolved "<self>" placeholder
  # in the jq filter, which meant .user.login=="<self>" could never match a real
  # GitHub username -- every read-back run silently fell through to "no draft found"
  # even when a pending review genuinely existed.
  READBACK_BLOCK=$(awk '/\*\*Read-Back Pass\*\*/,0' "$SKILL_MD")
  if echo "$READBACK_BLOCK" | grep -q '"<self>"'; then
    echo "REGRESSION: literal <self> placeholder found in Read-Back Pass (never resolves to a real login)" >&2
    return 1
  fi
  # gh api's --jq/-q flag takes exactly one jq query string -- it does not
  # support jq's own --arg flag. A prior version of this spec wrote
  # `gh api ... --jq --arg login "$SELF_LOGIN" '...'`, which is invalid: gh
  # api consumes the literal string "--arg" as its entire query and the rest
  # becomes stray positional arguments. The fix pipes to a standalone jq
  # instead, where --arg is valid.
  if echo "$READBACK_BLOCK" | grep -q -- '--jq --arg'; then
    echo "REGRESSION: 'gh api --jq --arg' is invalid syntax -- gh api's --jq takes one query string and does not support jq's --arg flag" >&2
    return 1
  fi
  echo "$READBACK_BLOCK" | grep -q "SELF_LOGIN=\$(gh api user"
  echo "$READBACK_BLOCK" | grep -q -- '| jq --arg login "\$SELF_LOGIN"'
}

@test "SKILL.md: Phase 4 skip gate includes --read-back (own-branch PR_NUMBER resolution)" {
  # Regression guard: --read-back on an own-branch invocation needs Phase 4 to
  # run so PR_NUMBER gets resolved before Phase 4b's Read-Back Pass fires.
  # Without --read-back in this gate, `/comprehensive-review --read-back` alone
  # skips Phase 4 entirely and the read-back has no PR to target.
  SKIP_GATE_LINE=$(grep -A1 "Skip entirely unless at least one of" "$SKILL_MD" | head -1)
  echo "$SKIP_GATE_LINE" | grep -q -- "--read-back"
}

@test "SKILL.md: Read-Back Pass step 0 names each of its three cross-phase preconditions" {
  # architecture-reviewer finding: the Read-Back Pass depends on a 3-4 link
  # precondition chain (Phase 4's widened skip-gate resolving PR_NUMBER,
  # Phase 4b steps 0/0b resolving PROJECT_ID/SHAs, and its own SELF_LOGIN
  # resolution because step 0c is scoped away from it) enforced only by
  # prose. This test doesn't make the chain structurally enforced (not
  # possible in a markdown orchestrator), but it does ensure step 0 keeps
  # naming all three, so a future edit that silently drops one of these
  # cross-references at least loses a grep match here.
  STEP0_BLOCK=$(awk '/^\*\*Read-Back Pass\*\*/,/^1\. \*\*Fetch the human/' "$SKILL_MD")
  echo "$STEP0_BLOCK" | grep -q "PR_NUMBER"
  echo "$STEP0_BLOCK" | grep -q "PROJECT_ID"
  echo "$STEP0_BLOCK" | grep -qi "SELF_LOGIN"
}

@test "SKILL.md: GitHub read-back does not re-attempt Stage draft review (would 422)" {
  # Regression guard: GitHub's pending-review create endpoint only accepts
  # comments at creation time (see PROVIDERS.md's "No append path" note). If
  # the Read-Back Pass tried to call the create OP a second time to append
  # net-new findings, it would 422 against the one-pending-review-per-PR
  # limit. GitHub must report net-new findings in the terminal instead.
  READ_BACK_BLOCK=$(awk '/\*\*Read-Back Pass\*\*/,/### Phase 5/' "$SKILL_MD")
  echo "$READ_BACK_BLOCK" | grep -qi "terminal only\|do \*\*NOT\*\* attempt to stage"
  echo "$READ_BACK_BLOCK" | grep -qi "doesn.t support appending\|only accepts comments at creation time\|would 422"
}

@test "SKILL.md: GitLab read-back net-new staging re-fetches MR_VERSION instead of reusing entry-time SHAs" {
  # edge-case-hunter finding: the SHAs used to stage net-new draft notes are
  # captured once at Phase 4b entry (step 0b), but the actual staging POST
  # happens after the full analysis pipeline reruns and a user confirmation
  # prompt -- an arbitrarily long delay during which a new commit on the MR
  # would make those SHAs stale, either failing the POST with a confusing
  # generic warning or mispositioning the comment against a stale diff view.
  STAGE_NET_NEW_BLOCK=$(awk '/\*\*Stage net-new findings only/,/Never delete or overwrite/' "$SKILL_MD")
  GITLAB_STAGE_BULLET=$(echo "$STAGE_NET_NEW_BLOCK" | awk '/- \*\*GitLab:\*\*/,/- \*\*GitHub:\*\*/')
  echo "$GITLAB_STAGE_BULLET" | grep -qi "re-fetch.*MR_VERSION\|re-run step 0b"
}

@test "SKILL.md: --post-summary alone is unaffected by draft mode (scope guard)" {
  # Regression guard: drafting must be scoped to --post-findings only. If
  # --post-summary alone started staging a pending review/draft note, it
  # would silently consume GitHub's one-pending-review-per-PR slot and
  # collide with a subsequent --post-findings run.
  grep -qi "post-summary.*unaffected by.*draft\|unaffected by this feature" "$SKILL_MD"
}

@test "SKILL.md: follow-up GET for inline count is retained in draft mode (regression guard)" {
  # The GitHub POST /reviews response omits .comments even for PENDING reviews;
  # a regression here would silently report INLINE_POSTED_COUNT=0 always.
  # A prior version of this test did an unscoped whole-file grep for the
  # literal follow-up-GET path, which only ever appears in the pre-existing
  # PUBLISH-path bullet (untouched by this feature) — verified empirically
  # that deleting the draft-mode branch's own reference to reusing that GET
  # still left this test passing. Scope to the POST_MODE=draft GitHub bullet
  # specifically, which references the GET by prose ("the same follow-up GET
  # as the publish path") rather than repeating the literal endpoint string.
  DRAFT_STEP8_BLOCK=$(awk '/POST_MODE=draft.*use.*OP: Stage draft review/,/^9\. \*\*Cite/' "$SKILL_MD")
  echo "$DRAFT_STEP8_BLOCK" | grep -qi "same follow-up GET as the publish path"
}

# ---------------------------------------------------------------------------
# Documentation sync: README / CLAUDE.md / HELP.md mention the new flags
# (mirrors the existing --quick sync convention — a flag that isn't
# documented everywhere is a support burden waiting to happen)
# ---------------------------------------------------------------------------

@test "README.md: documents --draft/--publish/--read-back and the draft-by-default behavior" {
  grep -q "\-\-publish" "$README_MD"
  grep -q "\-\-read-back" "$README_MD"
  grep -qi "stages an editable draft by default\|draft by default" "$README_MD"
}

@test "CLAUDE.md: two-block scenario table documents draft staging" {
  grep -qi "staged as draft review" "$CLAUDE_MD"
}

@test "HELP.md: documents --draft/--publish/--read-back flags" {
  grep -q "\-\-publish" "$HELP_MD"
  grep -q "\-\-read-back" "$HELP_MD"
  grep -q "\-\-draft" "$HELP_MD"
}

# ---------------------------------------------------------------------------
# Gate decisions for synthetic fixture diffs
# ---------------------------------------------------------------------------

@test "gates: tiny docs-only diff: GATE_CODE_OR_INFRA=false, all security gates false" {
  printf '+Updated docs\n+More content\n' > "${WORK}/docs.diff"
  DIFF_FILE="${WORK}/docs.diff" DIFF_PATHS="README.md" \
    run bash "$GATE_SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "GATE_CODE_OR_INFRA=false"
  echo "$output" | grep -q "GATE_SECURITY_PATTERNS=false"
  echo "$output" | grep -q "GATE_ERROR_PATTERNS=false"
}

@test "gates: Go source with error handling: GATE_ERROR_PATTERNS=true, GATE_CODE_OR_INFRA=true" {
  printf '+if err != nil { return err }\n+func main() {}\n' > "${WORK}/go.diff"
  DIFF_FILE="${WORK}/go.diff" DIFF_PATHS="cmd/main.go" \
    run bash "$GATE_SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "GATE_ERROR_PATTERNS=true"
  echo "$output" | grep -q "GATE_CODE_OR_INFRA=true"
}

@test "gates: dep manifest change triggers GATE_SECURITY_PATTERNS" {
  printf '+  "lodash": "4.17.21"\n' > "${WORK}/pkg.diff"
  DIFF_FILE="${WORK}/pkg.diff" DIFF_PATHS="package.json" \
    run bash "$GATE_SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "GATE_SECURITY_PATTERNS=true"
}

@test "gates: GitHub Actions workflow triggers GATE_CODE_OR_INFRA even if diff is docs-like" {
  printf '+    runs-on: ubuntu-latest\n' > "${WORK}/ci.diff"
  DIFF_FILE="${WORK}/ci.diff" DIFF_PATHS=".github/workflows/ci.yml" \
    run bash "$GATE_SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "GATE_CODE_OR_INFRA=true"
}

# ---------------------------------------------------------------------------
# run-cve-check.sh: category field present in output
# ---------------------------------------------------------------------------

@test "cve-check: findings include category=dependency-cve" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"
  # Must be named exactly 'go.mod' — the script matches on basename.
  cp "${FIXTURES_DIR}/cve/go.mod.replace-before-require" "${WORK}/go.mod"
  OSV_MOCK_FILE="${FIXTURES_DIR}/cve/osv-batch-critical.json" \
    run --separate-stderr bash "${SCRIPTS_DIR}/run-cve-check.sh" "${WORK}/go.mod"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].category == "dependency-cve"' >/dev/null
}
