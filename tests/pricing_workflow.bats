#!/usr/bin/env bats
# Tests for the "File or update issue" step of
# .github/workflows/model-pricing-check.yml.
#
# The step's shell is extracted from the workflow file itself and run against a
# fake `gh` on PATH, so the real create / dedupe / comment logic is exercised
# without touching GitHub. The fake logs every call to $GH_LOG and answers
# `gh issue list` and `gh issue view` from the environment.

bats_require_minimum_version 1.5.0

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq not available"
  python3 -c 'import yaml' 2>/dev/null || skip "python3 PyYAML not available"
  WF="${PRICING_WORKFLOW:-${BATS_TEST_DIRNAME}/../.github/workflows/model-pricing-check.yml}"
  WORK="$BATS_TEST_TMPDIR"
  export GH_LOG="$WORK/gh.log"; : > "$GH_LOG"
  export RUNNER_TEMP="$WORK/runner"; mkdir -p "$RUNNER_TEMP"

  # Extract the step's script from the workflow.
  python3 - "$WF" "$WORK/step.sh" <<'EOF'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
steps = wf["jobs"]["check"]["steps"]
run = next(s["run"] for s in steps if s.get("name") == "File or update issue")
open(sys.argv[2], "w").write("#!/usr/bin/env bash\n" + run)
EOF

  # Fake gh.
  mkdir -p "$WORK/bin"
  cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
  "label create") exit 0 ;;
  "issue list")   printf '%s' "${FAKE_EXISTING:-}" ;;
  "issue view")   cat "$FAKE_VIEW_JSON" ;;
  "issue create") echo "https://example.invalid/issues/1" ;;
  "issue comment") exit 0 ;;
  *) echo "unexpected gh call: $*" >&2; exit 99 ;;
esac
EOF
  chmod +x "$WORK/bin/gh"

  export GH_TOKEN="dummy" GH_REPO="owner/repo" GITHUB_SERVER_URL="https://example.invalid"
  export GITHUB_REPOSITORY="owner/repo" GITHUB_RUN_ID="42"
  export PATH="$WORK/bin:$PATH"
}

run_step() {
  RC="$1" run --separate-stderr bash --noprofile --norc -eo pipefail "$WORK/step.sh"
}

@test "step script extracts from the workflow and mentions both labels" {
  grep -q 'pricing-drift' "$WORK/step.sh"
  grep -q 'pricing-check-broken' "$WORK/step.sh"
}

@test "drift with no open issue: creates the label and one labeled issue containing the report" {
  printf -- '- **Changed:** Claude Sonnet 5.5 (was $2 in, now $3 in)\n' > "$RUNNER_TEMP/report.txt"
  run_step 1
  [ "$status" -eq 0 ]
  grep -q '^gh label create pricing-drift' "$GH_LOG"
  [ "$(grep -c '^gh issue create' "$GH_LOG")" -eq 1 ]
  grep -q 'issue create --title Model pricing drift detected' "$GH_LOG"
  grep -q -- '--label pricing-drift' "$GH_LOG"
  grep -qF 'Claude Sonnet 5.5 (was $2 in, now $3 in)' "$GH_LOG"
  ! grep -q '^gh issue comment' "$GH_LOG"
}

@test "drift when an open issue already contains this exact report: no new issue, no comment" {
  printf -- '- **Changed:** Claude Opus 5.5 (was $4 in, now $5 in)\n' > "$RUNNER_TEMP/report.txt"
  jq -n --arg b $'body\n```\n- **Changed:** Claude Opus 5.5 (was $4 in, now $5 in)\n```' \
    '{body:$b, comments:[]}' > "$WORK/view.json"
  FAKE_EXISTING=77 FAKE_VIEW_JSON="$WORK/view.json" run_step 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"already contains this report"* ]]
  ! grep -q '^gh issue create' "$GH_LOG"
  ! grep -q '^gh issue comment' "$GH_LOG"
}

@test "drift when an open issue has a different report: comments once, does not create" {
  printf -- '- **Added:** Claude Opus 6 ($6 in)\n' > "$RUNNER_TEMP/report.txt"
  jq -n '{body:"old report", comments:[{body:"earlier comment"}]}' > "$WORK/view.json"
  FAKE_EXISTING=77 FAKE_VIEW_JSON="$WORK/view.json" run_step 1
  [ "$status" -eq 0 ]
  [ "$(grep -c '^gh issue comment 77' "$GH_LOG")" -eq 1 ]
  grep -qF 'The report changed:' "$GH_LOG"
  grep -qF 'Claude Opus 6' "$GH_LOG"
  ! grep -q '^gh issue create' "$GH_LOG"
}

@test "drift when the report is already in a later comment: skipped" {
  printf -- '- **Removed:** Claude Haiku 3.5\n' > "$RUNNER_TEMP/report.txt"
  jq -n '{body:"old", comments:[{body:"- **Removed:** Claude Haiku 3.5"}]}' > "$WORK/view.json"
  FAKE_EXISTING=5 FAKE_VIEW_JSON="$WORK/view.json" run_step 1
  [ "$status" -eq 0 ]
  ! grep -q '^gh issue comment' "$GH_LOG"
}

@test "parse failure (rc 2): files the separate pricing-check-broken issue" {
  printf 'check-model-pricing: no pricing table found\n' > "$RUNNER_TEMP/report.txt"
  run_step 2
  [ "$status" -eq 0 ]
  grep -q '^gh label create pricing-check-broken' "$GH_LOG"
  grep -q 'issue create --title Pricing drift check could not parse the source page' "$GH_LOG"
  grep -q -- '--label pricing-check-broken' "$GH_LOG"
  ! grep -q -- '--label pricing-drift' "$GH_LOG"
}

@test "report text with shell metacharacters is passed through as data, never executed" {
  marker="$WORK/pwned"
  printf -- '%s\n' "- **Changed:** \$(touch $marker) \`touch $marker\` \"; touch $marker; \"" > "$RUNNER_TEMP/report.txt"
  run_step 1
  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
  grep -qF 'touch' "$GH_LOG"
  [ "$(grep -c '^gh issue create' "$GH_LOG")" -eq 1 ]
}

@test "a failing label create does not stop the issue from being filed" {
  printf -- '- **Added:** X\n' > "$RUNNER_TEMP/report.txt"
  # Replace the fake so label create fails (label already exists).
  sed -i 's/"label create") exit 0/"label create") exit 1/' "$WORK/bin/gh"
  run_step 1
  [ "$status" -eq 0 ]
  [ "$(grep -c '^gh issue create' "$GH_LOG")" -eq 1 ]
}
