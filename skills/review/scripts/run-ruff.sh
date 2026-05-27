#!/usr/bin/env bash
#
# run-ruff.sh — Run ruff on changed Python files and emit findings.
#
# Usage (two forms):
#   echo "$CHANGED_FILES" | ./run-ruff.sh        # stdin (used by SKILL.md)
#   ./run-ruff.sh <changed_files_list>            # positional arg
#
# Output:
#   JSON array of findings in the json-findings schema.
#   Outputs "[]" if ruff is unavailable, no Python files changed, or no issues found.
#
# Environment:
#   RUFF_MOCK_FILE   When set to a readable file path, read ruff JSON output
#                    from that file instead of running the binary.
#                    For offline testing only; unset in production.

set -euo pipefail

# Accept changed files list from stdin or $1
if [[ -n "${1:-}" ]]; then
  CHANGED_FILES="$1"
else
  CHANGED_FILES=$(cat)
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: jq not installed; ruff check skipped." >&2
  echo "[]"
  exit 0
fi

if [[ -z "${RUFF_MOCK_FILE:-}" ]] && ! command -v ruff >/dev/null 2>&1; then
  echo "WARNING: ruff not installed; ruff check skipped." >&2
  echo "[]"
  exit 0
fi

# Filter to Python files only
PY_FILES=()
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  case "$file" in
    *.py) [[ -f "$file" ]] && PY_FILES+=("$file") ;;
  esac
done <<< "$CHANGED_FILES"

if [[ ${#PY_FILES[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

# Run ruff (or read mock) — JSON output, no cache, exit-zero so lint
# findings don't abort the script
if [[ -n "${RUFF_MOCK_FILE:-}" ]]; then
  if [[ ! -r "$RUFF_MOCK_FILE" ]]; then
    echo "WARNING: RUFF_MOCK_FILE '${RUFF_MOCK_FILE}' is not readable." >&2
    echo "[]"
    exit 0
  fi
  RUFF_OUTPUT=$(cat "$RUFF_MOCK_FILE")
else
  RUFF_OUTPUT=$(ruff check --output-format=json --no-cache --exit-zero "${PY_FILES[@]}" 2>/dev/null || true)
fi

if [[ -z "$RUFF_OUTPUT" ]]; then
  echo "[]"
  exit 0
fi

# Convert ruff JSON to the findings schema.
# Severity mapping by rule prefix:
#   F (Pyflakes errors), E (pycodestyle errors) → High
#   W (pycodestyle warnings), C (convention)     → Medium
#   everything else (I, N, D, ANN, …)            → Low
FINDINGS=$(echo "$RUFF_OUTPUT" | jq -r '
  [
    .[]? |
    {
      severity: (
        if .code[0:1] == "F" or .code[0:1] == "E" then "High"
        elif .code[0:1] == "W" or .code[0:1] == "C"  then "Medium"
        else "Low"
        end
      ),
      confidence: 90,
      source: "ruff",
      file: .filename,
      line: .location.row,
      finding: ("\(.code): \(.message)"),
      remediation: (
        if .url then "See \(.url)"
        else "See https://docs.astral.sh/ruff/rules/\(.code)"
        end
      )
    }
  ]
' 2>/dev/null) || {
  echo "WARNING: ruff output could not be parsed; ruff findings skipped." >&2
  echo "[]"
  exit 0
}

echo "${FINDINGS:-[]}"
