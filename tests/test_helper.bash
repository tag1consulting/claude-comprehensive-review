#!/usr/bin/env bash
# test_helper.bash — shared paths and helpers for the comprehensive-review
# helper-script test suite.
#
# These tests exercise the deterministic helper scripts under
# skills/comprehensive-review/scripts/ entirely offline, using the *_MOCK_FILE
# environment variables each script supports. No network access is required.

# shellcheck disable=SC2034  # consumed by .bats files that load this helper
SCRIPTS_DIR="${CR_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/comprehensive-review/scripts" && pwd)}"
# shellcheck disable=SC2034
FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures" && pwd)"

# Close stdin for the test. Several scripts read their file list from stdin when
# called with no argument (for example `run "$SCRIPT" ""`), which blocks forever
# if the harness leaves stdin as an open pipe that never sends EOF. `load` sources
# this file inside the test, so the redirect applies to setup, the test body and
# teardown.
exec </dev/null

# Print a PATH equal to the current one but without <binary>. Every PATH entry
# that contains the binary is replaced by a mirror directory of symlinks to that
# entry's other files, so the remaining tools (jq, grep, ...) still resolve.
# Lets a test prove a script's "binary not installed" guard runs even on a machine
# where the binary is installed.
#
# Usage: PATH="$(path_without kube-linter)" run "$SCRIPT" ...
path_without() {
  local bin="$1" root dir out="" i=0 f
  root=$(mktemp -d "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/nopath-XXXXXX")
  local IFS=:
  local -a dirs
  read -ra dirs <<<"$PATH"
  for dir in "${dirs[@]}"; do
    if [[ -x "$dir/$bin" ]]; then
      i=$((i + 1))
      mkdir -p "$root/$i"
      # One ln call for the whole directory (per-file forks made this slow).
      # "ln -s a b c dir/" is valid on both GNU and BSD.
      local -a keep=()
      for f in "$dir"/*; do
        [[ "${f##*/}" == "$bin" ]] && continue
        [[ -e "$f" || -L "$f" ]] || continue  # unmatched glob in an empty directory
        keep+=("$f")
      done
      # Only an empty directory skips ln. A real ln failure must be loud: a
      # silently incomplete PATH makes tests fail with a misleading "command
      # not found", or pass for the wrong reason.
      if ((${#keep[@]} > 0)); then
        ln -s "${keep[@]}" "$root/$i/" || {
          echo "path_without: could not mirror $dir without $bin" >&2
          return 1
        }
      fi
      dir="$root/$i"
    fi
    out+="${out:+:}$dir"
  done
  printf '%s' "$out"
}

# Extract a single function definition from a script and eval it into the
# current shell, so it can be tested in isolation without sourcing the whole
# script (which would trigger the orchestration `set -euo pipefail` main loop).
#
# Brace-depth tracking skips content inside single-quoted strings (in_sq toggle),
# which handles the embedded awk programs in these scripts — their { } characters
# are at the top level of the single-quoted awk body, not inside bash single-quotes.
# Constraint: do NOT use this helper on functions containing { } inside bash
# double-quoted strings or heredocs, as those would miscount depth.
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
  if ! eval "$func_body"; then
    echo "ERROR: eval failed for function '${func_name}' from ${script}" >&2
    return 1
  fi
}
