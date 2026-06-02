#!/usr/bin/env bats
# Tests for run-trufflehog.sh.
# Uses TRUFFLEHOG_MOCK_FILE to bypass the binary entirely.

bats_require_minimum_version 1.5.0

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq not available"
  load test_helper
  SCRIPT="${SCRIPTS_DIR}/run-trufflehog.sh"
  TH_FIX="${FIXTURES_DIR}/trufflehog"
  WORK=$(mktemp -d)
}

teardown() {
  rm -rf "$WORK"
}

@test "trufflehog: verified secret reports Critical at source file path" {
  TRUFFLEHOG_MOCK_FILE="$TH_FIX/verified-secret.ndjson" run --separate-stderr "$SCRIPT" ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 1' >/dev/null
  echo "$output" | jq -e '.[0].severity == "Critical"' >/dev/null
  echo "$output" | jq -e '.[0].confidence == 95' >/dev/null
  echo "$output" | jq -e '.[0].file == "src/config.py"' >/dev/null
  echo "$output" | jq -e '.[0].line == 42' >/dev/null
  echo "$output" | jq -e '.[0].source == "trufflehog"' >/dev/null
}

@test "trufflehog: unverified secret in test fixture demoted to Low" {
  TRUFFLEHOG_MOCK_FILE="$TH_FIX/unverified-test-fixture.ndjson" run --separate-stderr "$SCRIPT" ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 1' >/dev/null
  echo "$output" | jq -e '.[0].severity == "Low"' >/dev/null
  echo "$output" | jq -e '.[0].confidence == 40' >/dev/null
  echo "$output" | jq -e '.[0].file | test("tests/fixtures")' >/dev/null
}

@test "trufflehog: unverified secret in source file reports High" {
  TRUFFLEHOG_MOCK_FILE="$TH_FIX/unverified-source.ndjson" run --separate-stderr "$SCRIPT" ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].severity == "High"' >/dev/null
  echo "$output" | jq -e '.[0].confidence == 85' >/dev/null
  echo "$output" | jq -e '.[0].file == "src/notifications.ts"' >/dev/null
}

@test "trufflehog: empty mock file returns empty array" {
  TRUFFLEHOG_MOCK_FILE="/dev/null" run --separate-stderr "$SCRIPT" ""
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "trufflehog: no changed files returns empty array" {
  unset TRUFFLEHOG_MOCK_FILE
  run --separate-stderr "$SCRIPT" ""
  # Skips gracefully when trufflehog is not installed (TRUFFLEHOG_MOCK_FILE unset)
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "trufflehog: finding at allowlisted path is suppressed when .trufflehog.yml exists" {
  # Copy the fixture allowlist config into $WORK so the script finds it in cwd
  cp "$TH_FIX/.trufflehog.yml" "$WORK/.trufflehog.yml"
  cd "$WORK"
  TRUFFLEHOG_MOCK_FILE="$TH_FIX/allowlisted-path.ndjson" run --separate-stderr "$SCRIPT" ""
  [ "$status" -eq 0 ]
  # The finding at vendor/autoload.php must be suppressed (output is empty array)
  echo "$output" | jq -e 'length == 0' >/dev/null
}

@test "trufflehog: finding at allowlisted path is NOT suppressed when .trufflehog.yml absent" {
  # Run from $WORK which has no .trufflehog.yml
  cd "$WORK"
  TRUFFLEHOG_MOCK_FILE="$TH_FIX/allowlisted-path.ndjson" run --separate-stderr "$SCRIPT" ""
  [ "$status" -eq 0 ]
  # No allowlist active, so the finding should be present
  echo "$output" | jq -e 'length == 1' >/dev/null
  echo "$output" | jq -e '.[0].file == "vendor/autoload.php"' >/dev/null
}

@test "trufflehog: allowlist suppresses findings for single-quoted and unquoted paths" {
  # Fixture .trufflehog.yml includes both single-quoted and unquoted list entries;
  # verify that findings at those paths are suppressed just like double-quoted ones.
  cp "$TH_FIX/.trufflehog.yml" "$WORK/.trufflehog.yml"
  cd "$WORK"

  # Single-quoted entry: - 'single-quoted/secret-mock.js'
  TRUFFLEHOG_MOCK_FILE="$TH_FIX/allowlisted-path-singlequote.ndjson" run --separate-stderr "$SCRIPT" ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 0' >/dev/null

  # Unquoted entry: - unquoted/legacy-fixture.php
  TRUFFLEHOG_MOCK_FILE="$TH_FIX/allowlisted-path-unquoted.ndjson" run --separate-stderr "$SCRIPT" ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 0' >/dev/null
}
