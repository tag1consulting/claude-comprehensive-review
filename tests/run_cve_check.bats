#!/usr/bin/env bats
# Tests for run-cve-check.sh.
#
# Two kinds of tests:
#   1. Parser-level: extract parse_go_mod() in isolation and assert the
#      ecosystem/name/version tuples it emits (covers issue #67).
#   2. End-to-end: feed a manifest plus an OSV_MOCK_FILE batch response and
#      assert the resulting findings JSON. Fully offline.

bats_require_minimum_version 1.5.0

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq not available"
  load test_helper
  SCRIPT="${SCRIPTS_DIR}/run-cve-check.sh"
  CVE_FIX="${FIXTURES_DIR}/cve"
  WORK=$(mktemp -d)
}

teardown() {
  rm -rf "$WORK"
}

# ---------------------------------------------------------------------------
# parse_go_mod — replace directive handling (#67)
# ---------------------------------------------------------------------------

@test "parse_go_mod: replace applies when require comes before replace (#67)" {
  load_function "$SCRIPT" parse_go_mod
  run parse_go_mod "$CVE_FIX/go.mod.require-before-replace"
  [ "$status" -eq 0 ]
  # The replaced module must resolve to the fork, regardless of file ordering.
  [[ "$output" == *"Go	example.com/fork	1.2.3"* ]]
  # The original module/version must NOT be queried.
  [[ "$output" != *"example.com/original	1.0.0"* ]]
  # Unreplaced modules pass through untouched.
  [[ "$output" == *"Go	example.com/safe	2.0.0"* ]]
}

@test "parse_go_mod: replace applies when replace comes before require" {
  load_function "$SCRIPT" parse_go_mod
  run parse_go_mod "$CVE_FIX/go.mod.replace-before-require"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Go	example.com/fork	1.2.3"* ]]
  [[ "$output" != *"example.com/original	1.0.0"* ]]
  [[ "$output" == *"Go	example.com/safe	2.0.0"* ]]
}

@test "parse_go_mod: local-path replace keeps original (cannot query local fork)" {
  load_function "$SCRIPT" parse_go_mod
  run parse_go_mod "$CVE_FIX/go.mod.local-replace"
  [ "$status" -eq 0 ]
  # A local replacement target (../local/fork) is not queryable; the original
  # module is left in place rather than emitting a bogus local path.
  [[ "$output" == *"Go	example.com/original	1.0.0"* ]]
  [[ "$output" != *"local"* ]]
}

@test "parse_go_mod: unclosed replace block does not skip require entries in pass 2" {
  load_function "$SCRIPT" parse_go_mod
  run parse_go_mod "$CVE_FIX/go.mod.unclosed-replace"
  [ "$status" -eq 0 ]
  # in_replace state must be reset at the pass-2 boundary; if it leaks,
  # all require lines in pass 2 are treated as replace lines and silently skipped.
  [[ "$output" == *"Go	example.com/safe	2.0.0"* ]]
}

# ---------------------------------------------------------------------------
# No-op paths
# ---------------------------------------------------------------------------

@test "cve-check: empty input returns empty array" {
  run --separate-stderr "$SCRIPT" ""
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "cve-check: no manifest files in input returns empty array" {
  run --separate-stderr "$SCRIPT" $'src/foo.go\nREADME.md'
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "cve-check: nonexistent manifest path returns empty array" {
  run --separate-stderr "$SCRIPT" "nonexistent/go.mod"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

# ---------------------------------------------------------------------------
# End-to-end with OSV batch mock
# ---------------------------------------------------------------------------

@test "cve-check: go.mod with critical CVE produces Critical finding with dependency-cve category" {
  cp "$CVE_FIX/go.mod.replace-before-require" "$WORK/go.mod"
  OSV_MOCK_FILE="$CVE_FIX/osv-batch-critical.json" run --separate-stderr "$SCRIPT" "$WORK/go.mod"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'type == "array" and length > 0' >/dev/null
  echo "$output" | jq -e '.[0].severity == "Critical"' >/dev/null
  echo "$output" | jq -e '.[0].agent == "dependency-check"' >/dev/null
  echo "$output" | jq -e '.[0].category == "dependency-cve"' >/dev/null
  echo "$output" | jq -e '.[0].file | endswith("go.mod")' >/dev/null
}

@test "cve-check: empty OSV batch response returns empty findings array" {
  cp "$CVE_FIX/go.mod.replace-before-require" "$WORK/go.mod"
  OSV_MOCK_FILE="$CVE_FIX/osv-batch-empty.json" run --separate-stderr "$SCRIPT" "$WORK/go.mod"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "cve-check: malformed OSV batch response falls through to empty array" {
  cp "$CVE_FIX/go.mod.replace-before-require" "$WORK/go.mod"
  OSV_MOCK_FILE="$CVE_FIX/osv-batch-malformed.json" run --separate-stderr "$SCRIPT" "$WORK/go.mod"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "cve-check: CVSS v4 vector maps to High (conservative fallback)" {
  cp "$CVE_FIX/go.mod.replace-before-require" "$WORK/go.mod"
  OSV_MOCK_FILE="$CVE_FIX/osv-batch-cvss4.json" run --separate-stderr "$SCRIPT" "$WORK/go.mod"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length > 0' >/dev/null
  echo "$output" | jq -e '.[0].severity == "High"' >/dev/null
  echo "$output" | jq -e '.[0].category == "dependency-cve"' >/dev/null
}
