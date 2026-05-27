#!/usr/bin/env bash
#
# run-shellcheck.sh — Run shellcheck on changed .sh files and output findings.
#
# Usage (two forms):
#   echo "$CHANGED_FILES" | ./run-shellcheck.sh        # stdin (used by SKILL.md)
#   ./run-shellcheck.sh <changed_files_list>            # positional arg
#
# Output:
#   JSON array of findings in the json-findings schema.
#   Outputs "[]" if no issues found or shellcheck is not available.
#
# Environment:
#   SHELLCHECK_MOCK_FILE  When set to a readable file path, read shellcheck JSON
#                         output from that file instead of running the binary.
#                         For offline testing only; unset in production.

set -euo pipefail

# Accept changed files list from stdin or $1
if [[ -n "${1:-}" ]]; then
  CHANGED_FILES="$1"
else
  CHANGED_FILES=$(cat)
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: jq not installed; shellcheck check skipped." >&2
  echo "[]"
  exit 0
fi

if [[ -z "${SHELLCHECK_MOCK_FILE:-}" ]] && ! command -v shellcheck &>/dev/null; then
  echo "WARNING: shellcheck not installed, skipping lint pass." >&2
  echo "[]"
  exit 0
fi

# Filter to .sh and .bash files
SHELL_FILES=()
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  case "$file" in
    *.sh|*.bash) [[ -f "$file" ]] && SHELL_FILES+=("$file") ;;
  esac
done <<< "$CHANGED_FILES"

if [[ ${#SHELL_FILES[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

# Mock path: treat mock file as shellcheck -f json1 output for the first file
if [[ -n "${SHELLCHECK_MOCK_FILE:-}" ]]; then
  if [[ ! -r "$SHELLCHECK_MOCK_FILE" ]]; then
    echo "WARNING: SHELLCHECK_MOCK_FILE '${SHELLCHECK_MOCK_FILE}' is not readable." >&2
    echo "[]"
    exit 0
  fi
  SC_OUTPUT=$(cat "$SHELLCHECK_MOCK_FILE")
  FILE_FINDINGS=$(echo "$SC_OUTPUT" | jq -r --arg file "${SHELL_FILES[0]}" '
    [.comments[]? | select(.level == "warning" or .level == "error") | {
      severity: (if .level == "error" then "High" else "Medium" end),
      confidence: 95,
      source: "shellcheck",
      file: $file,
      line: .line,
      finding: ("SC\(.code): \(.message)"),
      remediation: ("See https://www.shellcheck.net/wiki/SC\(.code)")
    }]
  ' 2>/dev/null) || FILE_FINDINGS="[]"
  echo "${FILE_FINDINGS:-[]}"
  exit 0
fi

# Run shellcheck on each file, collect JSON output
FINDINGS="[]"
for file in "${SHELL_FILES[@]}"; do
  # Run shellcheck with JSON output (-f json1) at warning severity
  SC_OUTPUT=$(shellcheck -f json1 -S warning -- "$file" 2>/dev/null || true)
  [[ -z "$SC_OUTPUT" ]] && continue

  FILE_FINDINGS=$(echo "$SC_OUTPUT" | jq -r --arg file "$file" '
    [.comments[]? | select(.level == "warning" or .level == "error") | {
      severity: (if .level == "error" then "High" else "Medium" end),
      confidence: 95,
      source: "shellcheck",
      file: $file,
      line: .line,
      finding: ("SC\(.code): \(.message)"),
      remediation: ("See https://www.shellcheck.net/wiki/SC\(.code)")
    }]
  ' 2>/dev/null) || {
    echo "WARNING: jq failed to parse shellcheck output for ${file}; skipping." >&2
    continue
  }

  FINDINGS=$(printf '%s\n%s' "$FINDINGS" "$FILE_FINDINGS" | jq -s '.[0] + .[1]')
done

printf '%s\n' "$FINDINGS"
