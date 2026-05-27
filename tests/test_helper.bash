#!/usr/bin/env bash
# test_helper.bash — shared paths and helpers for the comprehensive-review
# helper-script test suite.
#
# These tests exercise the deterministic helper scripts under
# skills/comprehensive-review/scripts/ entirely offline, using the *_MOCK_FILE
# environment variables each script supports. No network access is required.

# shellcheck disable=SC2034  # consumed by .bats files that load this helper
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/comprehensive-review/scripts" && pwd)"
# shellcheck disable=SC2034
FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures" && pwd)"

# Extract a single function definition from a script and eval it into the
# current shell, so it can be tested in isolation without sourcing the whole
# script (which would trigger the orchestration `set -euo pipefail` main loop).
#
# Brace-depth tracking ignores braces inside single-quoted strings (the awk
# bodies in these scripts are single-quoted), which is sufficient for the
# functions under test. It does NOT handle braces inside double-quoted strings
# or heredocs — keep extracted functions free of those.
#
# Usage: load_function <script_path> <function_name>
load_function() {
  local script="$1" func_name="$2" func_body
  func_body=$(awk -v fname="${func_name}" '
    $1 == fname"()" { found=1; depth=0; started=0 }
    found {
      n = split($0, chars, "")
      in_sq = 0
      for (i = 1; i <= n; i++) {
        c = chars[i]
        if (c == "'"'"'") { in_sq = !in_sq; continue }
        if (in_sq) continue
        if (c == "{") { depth++; started=1 }
        if (c == "}") depth--
      }
      body = body $0 "\n"
      if (started && depth == 0 && body != "") { print body; exit }
    }
  ' "$script")

  if [[ -z "$func_body" ]]; then
    echo "ERROR: Could not extract function '${func_name}' from ${script}" >&2
    return 1
  fi
  eval "$func_body"
}
