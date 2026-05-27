#!/usr/bin/env bash
#
# run-semgrep.sh — Run semgrep on changed files and emit findings.
#
# Usage (two forms):
#   echo "$CHANGED_FILES" | ./run-semgrep.sh        # stdin (used by SKILL.md)
#   ./run-semgrep.sh <changed_files_list>            # positional arg
#
# Output:
#   JSON array of findings in the json-findings schema.
#   Outputs "[]" if semgrep is unavailable, no files match, or no issues found.
#
# Environment:
#   SEMGREP_MOCK_FILE   When set to a readable file path, read semgrep JSON
#                       output from that file instead of running the binary.
#                       For offline testing only; unset in production.

set -euo pipefail

# Accept changed files list from stdin or $1
if [[ -n "${1:-}" ]]; then
  CHANGED_FILES="$1"
else
  CHANGED_FILES=$(cat)
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: jq not installed; semgrep check skipped." >&2
  echo "[]"
  exit 0
fi

if [[ -z "${SEMGREP_MOCK_FILE:-}" ]] && ! command -v semgrep >/dev/null 2>&1; then
  echo "WARNING: semgrep not installed; semgrep check skipped." >&2
  echo "[]"
  exit 0
fi

# Collect files that exist on disk (semgrep only scans present files)
TARGET_FILES=()
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  [[ -f "$file" ]] && TARGET_FILES+=("$file")
done <<< "$CHANGED_FILES"

if [[ ${#TARGET_FILES[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

# Run semgrep (or read mock) — --json --config=auto scans with default ruleset
if [[ -n "${SEMGREP_MOCK_FILE:-}" ]]; then
  if [[ ! -r "$SEMGREP_MOCK_FILE" ]]; then
    echo "WARNING: SEMGREP_MOCK_FILE '${SEMGREP_MOCK_FILE}' is not readable." >&2
    echo "[]"
    exit 0
  fi
  SEMGREP_OUTPUT=$(cat "$SEMGREP_MOCK_FILE")
else
  SEMGREP_STDERR=$(mktemp)
  trap 'rm -f "$SEMGREP_STDERR"' EXIT
  SEMGREP_OUTPUT=$(semgrep --json --config=auto --quiet "${TARGET_FILES[@]}" 2>"$SEMGREP_STDERR") || true
  if [[ -z "$SEMGREP_OUTPUT" ]]; then
    echo "WARNING: semgrep produced no output — possible network failure or config error. stderr: $(cat "$SEMGREP_STDERR")" >&2
    echo "[]"
    exit 0
  fi
fi

if [[ -z "$SEMGREP_OUTPUT" ]]; then
  echo "[]"
  exit 0
fi

# Convert semgrep JSON results to the findings schema
FINDINGS=$(echo "$SEMGREP_OUTPUT" | jq -r '
  [
    .results[]? |
    {
      severity: (
        if .extra.severity == "ERROR"     then "High"
        elif .extra.severity == "WARNING" then "Medium"
        else "Low"
        end
      ),
      confidence: 90,
      source: "semgrep",
      file: .path,
      line: .start.line,
      finding: ("\(.check_id): \(.extra.message)"),
      remediation: (
        if .extra.metadata.references[0] then
          "See \(.extra.metadata.references[0])"
        else
          "Review the semgrep rule: \(.check_id)"
        end
      )
    }
  ]
' 2>/dev/null) || {
  echo "WARNING: semgrep output could not be parsed; semgrep findings skipped." >&2
  echo "[]"
  exit 0
}

echo "${FINDINGS:-[]}"
