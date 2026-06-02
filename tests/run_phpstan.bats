#!/usr/bin/env bats
# Tests for run-phpstan.sh. Uses PHPSTAN_MOCK_FILE to bypass the binary.

bats_require_minimum_version 1.5.0

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq not available"
  load test_helper
  SCRIPT="${SCRIPTS_DIR}/run-phpstan.sh"
  PHPSTAN_FIX="${FIXTURES_DIR}/phpstan"
  WORK=$(mktemp -d)
}

teardown() {
  rm -rf "$WORK"
}

# ---------------------------------------------------------------------------
# No-op paths
# ---------------------------------------------------------------------------

@test "phpstan: empty input returns empty array" {
  PHPSTAN_MOCK_FILE="$PHPSTAN_FIX/phpstan-empty.json" run --separate-stderr "$SCRIPT" ""
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "phpstan: non-PHP file returns empty array" {
  touch "$WORK/app.py"
  PHPSTAN_MOCK_FILE="$PHPSTAN_FIX/phpstan-empty.json" run --separate-stderr "$SCRIPT" "$WORK/app.py"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "phpstan: nonexistent PHP file returns empty array" {
  PHPSTAN_MOCK_FILE="$PHPSTAN_FIX/phpstan-empty.json" run --separate-stderr "$SCRIPT" "nonexistent/MyService.php"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "phpstan: empty files object returns empty array" {
  touch "$WORK/MyService.php"
  PHPSTAN_MOCK_FILE="$PHPSTAN_FIX/phpstan-empty.json" run --separate-stderr "$SCRIPT" "$WORK/MyService.php"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "phpstan: malformed output falls through safely" {
  touch "$WORK/MyService.php"
  PHPSTAN_MOCK_FILE="$PHPSTAN_FIX/phpstan-malformed.json" run --separate-stderr "$SCRIPT" "$WORK/MyService.php"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "phpstan: binary missing returns empty array" {
  unset PHPSTAN_MOCK_FILE
  run --separate-stderr "$SCRIPT" "src/MyService.php"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

# ---------------------------------------------------------------------------
# File extension matching
# ---------------------------------------------------------------------------

@test "phpstan: .php extension triggers scan" {
  touch "$WORK/MyService.php"
  PHPSTAN_MOCK_FILE="$PHPSTAN_FIX/phpstan-error.json" run --separate-stderr "$SCRIPT" "$WORK/MyService.php"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length > 0' >/dev/null
}

@test "phpstan: .module extension triggers scan" {
  touch "$WORK/my_module.module"
  PHPSTAN_MOCK_FILE="$PHPSTAN_FIX/phpstan-error.json" run --separate-stderr "$SCRIPT" "$WORK/my_module.module"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length > 0' >/dev/null
}

# ---------------------------------------------------------------------------
# Schema conformance
# ---------------------------------------------------------------------------

@test "phpstan: findings conform to required schema" {
  touch "$WORK/MyService.php"
  PHPSTAN_MOCK_FILE="$PHPSTAN_FIX/phpstan-error.json" run --separate-stderr "$SCRIPT" "$WORK/MyService.php"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '
    all(.[]; has("severity") and has("confidence") and has("source")
        and has("file") and has("line") and has("finding") and has("remediation"))
  ' >/dev/null
}

@test "phpstan: source field is phpstan on all findings" {
  touch "$WORK/MyService.php"
  PHPSTAN_MOCK_FILE="$PHPSTAN_FIX/phpstan-error.json" run --separate-stderr "$SCRIPT" "$WORK/MyService.php"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .source == "phpstan")' >/dev/null
}

@test "phpstan: severity is High on all findings" {
  touch "$WORK/MyService.php"
  PHPSTAN_MOCK_FILE="$PHPSTAN_FIX/phpstan-error.json" run --separate-stderr "$SCRIPT" "$WORK/MyService.php"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .severity == "High")' >/dev/null
}

@test "phpstan: confidence is 85 on all findings" {
  touch "$WORK/MyService.php"
  PHPSTAN_MOCK_FILE="$PHPSTAN_FIX/phpstan-error.json" run --separate-stderr "$SCRIPT" "$WORK/MyService.php"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; .confidence == 85)' >/dev/null
}

@test "phpstan: finding text contains error message" {
  touch "$WORK/MyService.php"
  PHPSTAN_MOCK_FILE="$PHPSTAN_FIX/phpstan-error.json" run --separate-stderr "$SCRIPT" "$WORK/MyService.php"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].finding | test("PHPStan|NodeInterface|string given"; "i")' >/dev/null
}

@test "phpstan: remediation includes phpstan.org URL" {
  touch "$WORK/MyService.php"
  PHPSTAN_MOCK_FILE="$PHPSTAN_FIX/phpstan-error.json" run --separate-stderr "$SCRIPT" "$WORK/MyService.php"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].remediation | test("phpstan.org")' >/dev/null
}

# ---------------------------------------------------------------------------
# stdin input contract
# ---------------------------------------------------------------------------

@test "phpstan: accepts file list via stdin" {
  touch "$WORK/MyService.php"
  PHPSTAN_MOCK_FILE="$PHPSTAN_FIX/phpstan-error.json" run --separate-stderr bash -c \
    "echo '$WORK/MyService.php' | '$SCRIPT'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length > 0' >/dev/null
}
