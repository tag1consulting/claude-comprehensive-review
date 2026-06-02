#!/usr/bin/env bats
# Tests for run-tflint.sh. Uses TFLINT_MOCK_FILE to bypass the binary.

bats_require_minimum_version 1.5.0

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq not available"
  load test_helper
  SCRIPT="${SCRIPTS_DIR}/run-tflint.sh"
  TF_FIX="${FIXTURES_DIR}/tflint"
  WORK=$(mktemp -d)
}

teardown() {
  rm -rf "$WORK"
}

# ---------------------------------------------------------------------------
# No-op paths
# ---------------------------------------------------------------------------

@test "tflint: empty input returns empty array" {
  TFLINT_MOCK_FILE="$TF_FIX/tflint-empty.json" run --separate-stderr "$SCRIPT" ""
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "tflint: non-Terraform file returns empty array" {
  touch "$WORK/app.py"
  TFLINT_MOCK_FILE="$TF_FIX/tflint-empty.json" run --separate-stderr "$SCRIPT" "$WORK/app.py"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "tflint: nonexistent TF file returns empty array" {
  TFLINT_MOCK_FILE="$TF_FIX/tflint-empty.json" run --separate-stderr "$SCRIPT" "nonexistent/main.tf"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "tflint: empty issues array returns empty array" {
  touch "$WORK/main.tf"
  TFLINT_MOCK_FILE="$TF_FIX/tflint-empty.json" run --separate-stderr "$SCRIPT" "$WORK/main.tf"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "tflint: malformed output falls through safely" {
  touch "$WORK/main.tf"
  TFLINT_MOCK_FILE="$TF_FIX/tflint-malformed.json" run --separate-stderr "$SCRIPT" "$WORK/main.tf"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "tflint: binary missing returns empty array" {
  unset TFLINT_MOCK_FILE
  run --separate-stderr "$SCRIPT" "main.tf"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

# ---------------------------------------------------------------------------
# File extension matching
# ---------------------------------------------------------------------------

@test "tflint: .tf extension triggers scan" {
  touch "$WORK/main.tf"
  TFLINT_MOCK_FILE="$TF_FIX/tflint-error.json" run --separate-stderr "$SCRIPT" "$WORK/main.tf"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length > 0' >/dev/null
}

@test "tflint: .tfvars extension triggers scan" {
  touch "$WORK/terraform.tfvars"
  TFLINT_MOCK_FILE="$TF_FIX/tflint-error.json" run --separate-stderr "$SCRIPT" "$WORK/terraform.tfvars"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length > 0' >/dev/null
}

# ---------------------------------------------------------------------------
# Severity mapping
# ---------------------------------------------------------------------------

@test "tflint: rule severity error maps to High" {
  touch "$WORK/main.tf"
  TFLINT_MOCK_FILE="$TF_FIX/tflint-error.json" run --separate-stderr "$SCRIPT" "$WORK/main.tf"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].severity == "High"' >/dev/null
}

@test "tflint: rule severity warning maps to Medium" {
  touch "$WORK/variables.tf"
  TFLINT_MOCK_FILE="$TF_FIX/tflint-warning.json" run --separate-stderr "$SCRIPT" "$WORK/variables.tf"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].severity == "Medium"' >/dev/null
}

# ---------------------------------------------------------------------------
# Schema conformance
# ---------------------------------------------------------------------------

@test "tflint: findings conform to required schema" {
  touch "$WORK/main.tf"
  TFLINT_MOCK_FILE="$TF_FIX/tflint-error.json" run --separate-stderr "$SCRIPT" "$WORK/main.tf"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    all(.[]; has("severity") and has("confidence") and has("source")
        and has("file") and has("line") and has("finding") and has("remediation"))
  ' >/dev/null
}

@test "tflint: source field is tflint on all findings" {
  touch "$WORK/main.tf"
  TFLINT_MOCK_FILE="$TF_FIX/tflint-error.json" run --separate-stderr "$SCRIPT" "$WORK/main.tf"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .source == "tflint")' >/dev/null
}

@test "tflint: confidence is 90 on all findings" {
  touch "$WORK/main.tf"
  TFLINT_MOCK_FILE="$TF_FIX/tflint-error.json" run --separate-stderr "$SCRIPT" "$WORK/main.tf"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .confidence == 90)' >/dev/null
}

@test "tflint: finding text contains rule name" {
  touch "$WORK/main.tf"
  TFLINT_MOCK_FILE="$TF_FIX/tflint-error.json" run --separate-stderr "$SCRIPT" "$WORK/main.tf"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].finding | test("aws_instance_invalid_type")' >/dev/null
}

@test "tflint: remediation includes rule link when present" {
  touch "$WORK/main.tf"
  TFLINT_MOCK_FILE="$TF_FIX/tflint-error.json" run --separate-stderr "$SCRIPT" "$WORK/main.tf"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].remediation | test("https://")' >/dev/null
}

# ---------------------------------------------------------------------------
# stdin input contract
# ---------------------------------------------------------------------------

@test "tflint: accepts file list via stdin" {
  touch "$WORK/main.tf"
  TFLINT_MOCK_FILE="$TF_FIX/tflint-error.json" run --separate-stderr bash -c \
    "echo '$WORK/main.tf' | '$SCRIPT'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length > 0' >/dev/null
}
