#!/usr/bin/env bats
# Tests for run-eslint.sh. Uses ESLINT_MOCK_FILE to bypass the binary.

bats_require_minimum_version 1.5.0

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq not available"
  load test_helper
  SCRIPT="${SCRIPTS_DIR}/run-eslint.sh"
  ESLINT_FIX="${FIXTURES_DIR}/eslint"
  WORK=$(mktemp -d)
  # Create a minimal ESLint config so the no-config check does not block.
  # Set GITHUB_WORKSPACE so config detection finds it regardless of test CWD.
  touch "$WORK/.eslintrc.json"
  export GITHUB_WORKSPACE="$WORK"
}

teardown() {
  rm -rf "$WORK"
  unset GITHUB_WORKSPACE
}

# ---------------------------------------------------------------------------
# No-op paths
# ---------------------------------------------------------------------------

@test "eslint: empty input returns empty array" {
  ESLINT_MOCK_FILE="$ESLINT_FIX/eslint-empty.json" run --separate-stderr "$SCRIPT" ""
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "eslint: non-JS/TS file returns empty array" {
  touch "$WORK/app.py"
  ESLINT_MOCK_FILE="$ESLINT_FIX/eslint-empty.json" run --separate-stderr "$SCRIPT" "$WORK/app.py"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "eslint: nonexistent JS file returns empty array" {
  ESLINT_MOCK_FILE="$ESLINT_FIX/eslint-empty.json" run --separate-stderr "$SCRIPT" "nonexistent/file.ts"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "eslint: empty mock output returns empty array" {
  touch "$WORK/Button.tsx"
  ESLINT_MOCK_FILE="$ESLINT_FIX/eslint-empty.json" run --separate-stderr "$SCRIPT" "$WORK/Button.tsx"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "eslint: malformed output falls through safely" {
  touch "$WORK/Button.tsx"
  ESLINT_MOCK_FILE="$ESLINT_FIX/eslint-malformed.json" run --separate-stderr "$SCRIPT" "$WORK/Button.tsx"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "eslint: binary missing returns empty array" {
  unset ESLINT_MOCK_FILE
  # No node_modules and npx not available in CI PATH for eslint; expects skip.
  run --separate-stderr "$SCRIPT" "src/app.ts"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

# ---------------------------------------------------------------------------
# File extension matching
# ---------------------------------------------------------------------------

@test "eslint: .tsx extension triggers scan" {
  touch "$WORK/Button.tsx"
  ESLINT_MOCK_FILE="$ESLINT_FIX/eslint-error.json" run --separate-stderr "$SCRIPT" "$WORK/Button.tsx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length > 0' >/dev/null
}

@test "eslint: .ts extension triggers scan" {
  touch "$WORK/utils.ts"
  ESLINT_MOCK_FILE="$ESLINT_FIX/eslint-error.json" run --separate-stderr "$SCRIPT" "$WORK/utils.ts"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length > 0' >/dev/null
}

@test "eslint: .mjs extension triggers scan" {
  touch "$WORK/config.mjs"
  ESLINT_MOCK_FILE="$ESLINT_FIX/eslint-error.json" run --separate-stderr "$SCRIPT" "$WORK/config.mjs"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length > 0' >/dev/null
}

# ---------------------------------------------------------------------------
# Severity mapping
# ---------------------------------------------------------------------------

@test "eslint: severity 2 (error) maps to High" {
  touch "$WORK/Button.tsx"
  ESLINT_MOCK_FILE="$ESLINT_FIX/eslint-error.json" run --separate-stderr "$SCRIPT" "$WORK/Button.tsx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].severity == "High"' >/dev/null
}

@test "eslint: severity 1 (warning) maps to Medium" {
  touch "$WORK/format.ts"
  ESLINT_MOCK_FILE="$ESLINT_FIX/eslint-warning.json" run --separate-stderr "$SCRIPT" "$WORK/format.ts"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].severity == "Medium"' >/dev/null
}

# ---------------------------------------------------------------------------
# Schema conformance
# ---------------------------------------------------------------------------

@test "eslint: findings conform to required schema" {
  touch "$WORK/Button.tsx"
  ESLINT_MOCK_FILE="$ESLINT_FIX/eslint-error.json" run --separate-stderr "$SCRIPT" "$WORK/Button.tsx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    all(.[]; has("severity") and has("confidence") and has("source")
        and has("file") and has("line") and has("finding") and has("remediation"))
  ' >/dev/null
}

@test "eslint: source field is eslint on all findings" {
  touch "$WORK/Button.tsx"
  ESLINT_MOCK_FILE="$ESLINT_FIX/eslint-error.json" run --separate-stderr "$SCRIPT" "$WORK/Button.tsx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .source == "eslint")' >/dev/null
}

@test "eslint: confidence is 90 on all findings" {
  touch "$WORK/Button.tsx"
  ESLINT_MOCK_FILE="$ESLINT_FIX/eslint-error.json" run --separate-stderr "$SCRIPT" "$WORK/Button.tsx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .confidence == 90)' >/dev/null
}

@test "eslint: finding text contains rule ID" {
  touch "$WORK/Button.tsx"
  ESLINT_MOCK_FILE="$ESLINT_FIX/eslint-error.json" run --separate-stderr "$SCRIPT" "$WORK/Button.tsx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].finding | test("no-unused-vars")' >/dev/null
}

@test "eslint: remediation includes eslint.org docs URL" {
  touch "$WORK/Button.tsx"
  ESLINT_MOCK_FILE="$ESLINT_FIX/eslint-error.json" run --separate-stderr "$SCRIPT" "$WORK/Button.tsx"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].remediation | test("eslint.org")' >/dev/null
}

# ---------------------------------------------------------------------------
# stdin input contract
# ---------------------------------------------------------------------------

@test "eslint: accepts file list via stdin" {
  touch "$WORK/Button.tsx"
  ESLINT_MOCK_FILE="$ESLINT_FIX/eslint-error.json" run --separate-stderr bash -c \
    "echo '$WORK/Button.tsx' | '$SCRIPT'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length > 0' >/dev/null
}
