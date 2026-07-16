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

@test "SKILL.md: --post-findings defaults to draft mode, --publish opts into publishing" {
  grep -q "\-\-publish" "$SKILL_MD"
  grep -q "\-\-draft" "$SKILL_MD"
  grep -qi "POST_MODE=draft" "$SKILL_MD"
}

@test "SKILL.md: --publish and --draft are documented as mutually exclusive" {
  grep -q "\-\-publish and --draft are mutually exclusive" "$SKILL_MD"
}

@test "SKILL.md: GitHub pending-review one-per-PR pre-check is documented" {
  grep -qi "already have a pending review" "$SKILL_MD"
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
  echo "$READBACK_BLOCK" | grep -q "SELF_LOGIN=\$(gh api user"
  echo "$READBACK_BLOCK" | grep -q -- '--arg login "\$SELF_LOGIN"'
}

@test "SKILL.md: Phase 4 skip gate includes --read-back (own-branch PR_NUMBER resolution)" {
  # Regression guard: --read-back on an own-branch invocation needs Phase 4 to
  # run so PR_NUMBER gets resolved before Phase 4b's Read-Back Pass fires.
  # Without --read-back in this gate, `/comprehensive-review --read-back` alone
  # skips Phase 4 entirely and the read-back has no PR to target.
  SKIP_GATE_LINE=$(grep -A1 "Skip entirely unless at least one of" "$SKILL_MD" | head -1)
  echo "$SKIP_GATE_LINE" | grep -q -- "--read-back"
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
