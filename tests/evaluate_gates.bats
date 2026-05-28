#!/usr/bin/env bats
# Tests for evaluate-gates.sh.
# Creates temp diff files and file-path lists and asserts the correct gate values.

bats_require_minimum_version 1.5.0

setup() {
  load test_helper
  SCRIPT="${SCRIPTS_DIR}/evaluate-gates.sh"
  WORK=$(mktemp -d)
}

teardown() {
  rm -rf "$WORK"
}

# Helper: run the gate script with custom DIFF_FILE content and DIFF_PATHS list.
run_gates() {
  local diff_content="$1" diff_paths="$2"
  local diff_file="${WORK}/test.diff"
  printf '%s\n' "$diff_content" > "$diff_file"
  DIFF_FILE="$diff_file" DIFF_PATHS="$diff_paths" run bash "$SCRIPT"
}

# Parse a gate flag value from sourced output (e.g., "GATE_ERROR_PATTERNS=true" → "true").
gate_value() {
  local gate_name="$1"
  echo "$output" | grep "^${gate_name}=" | cut -d= -f2
}

# ---------------------------------------------------------------------------
# Fallback behavior
# ---------------------------------------------------------------------------

@test "gates: missing DIFF_FILE defaults all gates to true" {
  DIFF_FILE="" DIFF_PATHS="src/foo.go" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(gate_value GATE_ERROR_PATTERNS)" = "true" ]
  [ "$(gate_value GATE_CONTROL_FLOW)" = "true" ]
  [ "$(gate_value GATE_SECURITY_PATTERNS)" = "true" ]
  [ "$(gate_value GATE_CODE_OR_INFRA)" = "true" ]
}

@test "gates: nonexistent DIFF_FILE defaults all gates to true" {
  DIFF_FILE="/nonexistent/path.diff" DIFF_PATHS="src/foo.go" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(gate_value GATE_ERROR_PATTERNS)" = "true" ]
}

# ---------------------------------------------------------------------------
# GATE_ERROR_PATTERNS
# ---------------------------------------------------------------------------

@test "gates: diff with 'if err' triggers GATE_ERROR_PATTERNS" {
  run_gates $'+if err != nil {\n+  return err\n+}' "src/main.go"
  [ "$status" -eq 0 ]
  [ "$(gate_value GATE_ERROR_PATTERNS)" = "true" ]
}

@test "gates: diff with 'catch' triggers GATE_ERROR_PATTERNS" {
  run_gates $'+} catch (Exception e) {\n+  log.error(e);\n+}' "src/Service.java"
  [ "$status" -eq 0 ]
  [ "$(gate_value GATE_ERROR_PATTERNS)" = "true" ]
}

@test "gates: pure docs diff does not trigger GATE_ERROR_PATTERNS" {
  run_gates "+Updated README content with no code" "README.md"
  [ "$status" -eq 0 ]
  [ "$(gate_value GATE_ERROR_PATTERNS)" = "false" ]
}

# ---------------------------------------------------------------------------
# GATE_CONTROL_FLOW
# ---------------------------------------------------------------------------

@test "gates: diff with added 'if' statement triggers GATE_CONTROL_FLOW" {
  run_gates $'+if x > 0 {\n+  doSomething()\n+}' "src/main.go"
  [ "$status" -eq 0 ]
  [ "$(gate_value GATE_CONTROL_FLOW)" = "true" ]
}

@test "gates: removed 'if' (minus line) does not trigger GATE_CONTROL_FLOW" {
  run_gates $'-if x > 0 {\n-  doSomething()\n-}' "src/main.go"
  [ "$status" -eq 0 ]
  [ "$(gate_value GATE_CONTROL_FLOW)" = "false" ]
}

# ---------------------------------------------------------------------------
# GATE_SECURITY_PATTERNS
# ---------------------------------------------------------------------------

@test "gates: diff mentioning 'password' triggers GATE_SECURITY_PATTERNS" {
  run_gates "+const password = 'change-me'" "config/settings.py"
  [ "$status" -eq 0 ]
  [ "$(gate_value GATE_SECURITY_PATTERNS)" = "true" ]
}

@test "gates: go.mod in changed file paths triggers GATE_SECURITY_PATTERNS" {
  run_gates "+require example.com/foo v1.2.3" "go.mod"
  [ "$status" -eq 0 ]
  [ "$(gate_value GATE_SECURITY_PATTERNS)" = "true" ]
}

@test "gates: Dockerfile in file paths triggers GATE_SECURITY_PATTERNS" {
  run_gates "+FROM node:20" "Dockerfile"
  [ "$status" -eq 0 ]
  [ "$(gate_value GATE_SECURITY_PATTERNS)" = "true" ]
}

@test "gates: plain diff with no security content does not trigger GATE_SECURITY_PATTERNS" {
  run_gates "+Added a new helper function" "src/utils.go"
  [ "$status" -eq 0 ]
  [ "$(gate_value GATE_SECURITY_PATTERNS)" = "false" ]
}

# ---------------------------------------------------------------------------
# GATE_CODE_OR_INFRA
# ---------------------------------------------------------------------------

@test "gates: Go source file triggers GATE_CODE_OR_INFRA" {
  run_gates "+func foo() {}" "src/main.go"
  [ "$status" -eq 0 ]
  [ "$(gate_value GATE_CODE_OR_INFRA)" = "true" ]
}

@test "gates: GitHub Actions workflow triggers GATE_CODE_OR_INFRA" {
  run_gates "+    runs-on: ubuntu-latest" ".github/workflows/ci.yml"
  [ "$status" -eq 0 ]
  [ "$(gate_value GATE_CODE_OR_INFRA)" = "true" ]
}

@test "gates: only .md files do not trigger GATE_CODE_OR_INFRA" {
  run_gates "+Updated documentation" "docs/guide.md"
  [ "$status" -eq 0 ]
  [ "$(gate_value GATE_CODE_OR_INFRA)" = "false" ]
}

@test "gates: only CHANGELOG does not trigger GATE_CODE_OR_INFRA" {
  run_gates "+## v1.9.0" "CHANGELOG.md"
  [ "$status" -eq 0 ]
  [ "$(gate_value GATE_CODE_OR_INFRA)" = "false" ]
}
