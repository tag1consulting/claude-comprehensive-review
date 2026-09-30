#!/usr/bin/env bats
# Tests for the shared helpers in test_helper.bash.

bats_require_minimum_version 1.5.0

setup() {
  load test_helper
}

@test "path_without hides the binary but keeps the rest of the toolchain" {
  command -v bash >/dev/null   # any binary we can rely on being on PATH
  local p
  p="$(path_without bash)"
  # bash is hidden from the returned PATH...
  ! PATH="$p" command -v bash >/dev/null 2>&1
  # ...while other tools that lived in the same directories still resolve.
  PATH="$p" command -v ls >/dev/null
  PATH="$p" command -v grep >/dev/null
}

@test "path_without leaves PATH entries that do not contain the binary untouched" {
  local p
  p="$(path_without definitely-not-a-real-binary-xyz)"
  [ "$p" = "$PATH" ]
}

@test "path_without fails loudly when the mirror cannot be built" {
  # A fake ln that always fails, first on PATH.
  mkdir -p "$BATS_TEST_TMPDIR/failing"
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/failing/ln"
  chmod +x "$BATS_TEST_TMPDIR/failing/ln"
  PATH="$BATS_TEST_TMPDIR/failing:$PATH" run --separate-stderr path_without bash
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"path_without: could not mirror"* ]]
}
