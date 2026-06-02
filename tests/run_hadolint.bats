#!/usr/bin/env bats
# Tests for run-hadolint.sh. Uses HADOLINT_MOCK_FILE to bypass the binary.

bats_require_minimum_version 1.5.0

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq not available"
  load test_helper
  SCRIPT="${SCRIPTS_DIR}/run-hadolint.sh"
  HAD_FIX="${FIXTURES_DIR}/hadolint"
  WORK=$(mktemp -d)
}

teardown() {
  rm -rf "$WORK"
}

# ---------------------------------------------------------------------------
# No-op paths
# ---------------------------------------------------------------------------

@test "hadolint: empty input returns empty array" {
  HADOLINT_MOCK_FILE="$HAD_FIX/hadolint-empty.json" run --separate-stderr "$SCRIPT" ""
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "hadolint: non-Dockerfile file returns empty array" {
  touch "$WORK/app.py"
  HADOLINT_MOCK_FILE="$HAD_FIX/hadolint-empty.json" run --separate-stderr "$SCRIPT" "$WORK/app.py"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "hadolint: nonexistent Dockerfile returns empty array" {
  HADOLINT_MOCK_FILE="$HAD_FIX/hadolint-empty.json" run --separate-stderr "$SCRIPT" "nonexistent/Dockerfile"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "hadolint: empty mock output returns empty array" {
  touch "$WORK/Dockerfile"
  HADOLINT_MOCK_FILE="$HAD_FIX/hadolint-empty.json" run --separate-stderr "$SCRIPT" "$WORK/Dockerfile"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "hadolint: malformed output falls through safely" {
  touch "$WORK/Dockerfile"
  HADOLINT_MOCK_FILE="$HAD_FIX/hadolint-malformed.json" run --separate-stderr "$SCRIPT" "$WORK/Dockerfile"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "hadolint: binary missing returns empty array" {
  unset HADOLINT_MOCK_FILE
  run --separate-stderr "$SCRIPT" "Dockerfile"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

# ---------------------------------------------------------------------------
# File matching
# ---------------------------------------------------------------------------

@test "hadolint: bare Dockerfile triggers scan" {
  touch "$WORK/Dockerfile"
  HADOLINT_MOCK_FILE="$HAD_FIX/hadolint-error.json" run --separate-stderr "$SCRIPT" "$WORK/Dockerfile"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length > 0' >/dev/null
}

@test "hadolint: Dockerfile.prod variant triggers scan" {
  touch "$WORK/Dockerfile.prod"
  HADOLINT_MOCK_FILE="$HAD_FIX/hadolint-error.json" run --separate-stderr "$SCRIPT" "$WORK/Dockerfile.prod"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length > 0' >/dev/null
}

# ---------------------------------------------------------------------------
# Severity mapping
# ---------------------------------------------------------------------------

@test "hadolint: level error maps to High" {
  touch "$WORK/Dockerfile"
  HADOLINT_MOCK_FILE="$HAD_FIX/hadolint-error.json" run --separate-stderr "$SCRIPT" "$WORK/Dockerfile"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].severity == "High"' >/dev/null
}

@test "hadolint: level warning maps to Medium" {
  touch "$WORK/Dockerfile"
  HADOLINT_MOCK_FILE="$HAD_FIX/hadolint-warning.json" run --separate-stderr "$SCRIPT" "$WORK/Dockerfile"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].severity == "Medium"' >/dev/null
}

# ---------------------------------------------------------------------------
# Schema conformance
# ---------------------------------------------------------------------------

@test "hadolint: findings conform to required schema" {
  touch "$WORK/Dockerfile"
  HADOLINT_MOCK_FILE="$HAD_FIX/hadolint-error.json" run --separate-stderr "$SCRIPT" "$WORK/Dockerfile"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    all(.[]; has("severity") and has("confidence") and has("source")
        and has("file") and has("line") and has("finding") and has("remediation"))
  ' >/dev/null
}

@test "hadolint: source field is hadolint on all findings" {
  touch "$WORK/Dockerfile"
  HADOLINT_MOCK_FILE="$HAD_FIX/hadolint-error.json" run --separate-stderr "$SCRIPT" "$WORK/Dockerfile"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .source == "hadolint")' >/dev/null
}

@test "hadolint: finding text contains rule code" {
  touch "$WORK/Dockerfile"
  HADOLINT_MOCK_FILE="$HAD_FIX/hadolint-error.json" run --separate-stderr "$SCRIPT" "$WORK/Dockerfile"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].finding | test("DL3008")' >/dev/null
}

@test "hadolint: remediation includes hadolint wiki URL" {
  touch "$WORK/Dockerfile"
  HADOLINT_MOCK_FILE="$HAD_FIX/hadolint-error.json" run --separate-stderr "$SCRIPT" "$WORK/Dockerfile"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].remediation | test("hadolint")' >/dev/null
}

# ---------------------------------------------------------------------------
# stdin input contract
# ---------------------------------------------------------------------------

@test "hadolint: accepts file list via stdin" {
  touch "$WORK/Dockerfile"
  HADOLINT_MOCK_FILE="$HAD_FIX/hadolint-error.json" run --separate-stderr bash -c \
    "echo '$WORK/Dockerfile' | '$SCRIPT'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length > 0' >/dev/null
}
