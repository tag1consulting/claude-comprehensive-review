#!/usr/bin/env bash
#
# run-hadolint.sh — Run hadolint on changed Dockerfiles and emit findings.
#
# Usage (two forms):
#   echo "$CHANGED_FILES" | ./run-hadolint.sh       # stdin (used by SKILL.md)
#   ./run-hadolint.sh <changed_files_list>           # positional arg
#
# Output:
#   JSON array of findings in the json-findings schema.
#   Outputs "[]" if hadolint is unavailable, no Dockerfiles changed, or no issues found.
#
# Environment:
#   HADOLINT_MOCK_FILE   When set to a readable file path, read hadolint JSON
#                        output from that file instead of running the binary.
#                        For offline testing only; unset in production.

set -euo pipefail

# Accept changed files list from stdin or $1
if [[ -n "${1:-}" ]]; then
  CHANGED_FILES="$1"
else
  CHANGED_FILES=$(cat)
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: jq not installed; hadolint check skipped." >&2
  echo "[]"
  exit 0
fi

if [[ -z "${HADOLINT_MOCK_FILE:-}" ]] && ! command -v hadolint >/dev/null 2>&1; then
  echo "WARNING: hadolint not installed; hadolint check skipped." >&2
  echo "[]"
  exit 0
fi

# Filter to Dockerfile variants only
DOCKERFILE_FILES=()
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  case "$file" in
    Dockerfile|*/Dockerfile) [[ -f "$file" ]] && DOCKERFILE_FILES+=("$file") ;;
    Dockerfile.*|*/Dockerfile.*) [[ -f "$file" ]] && DOCKERFILE_FILES+=("$file") ;;
    *.dockerfile) [[ -f "$file" ]] && DOCKERFILE_FILES+=("$file") ;;
  esac
done <<< "$CHANGED_FILES"

if [[ ${#DOCKERFILE_FILES[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

if [[ -n "${HADOLINT_MOCK_FILE:-}" ]]; then
  if [[ ! -r "$HADOLINT_MOCK_FILE" ]]; then
    echo "WARNING: HADOLINT_MOCK_FILE '${HADOLINT_MOCK_FILE}' is not readable." >&2
    echo "[]"
    exit 0
  fi
  HADOLINT_OUTPUT=$(cat "$HADOLINT_MOCK_FILE")
else
  # --format json emits one JSON object per line (NDJSON); --no-fail prevents
  # non-zero exit when findings are present. Any remaining failure is a real error.
  HADOLINT_STDERR=$(mktemp)
  HADOLINT_OUTPUT=$(hadolint --format json --no-fail "${DOCKERFILE_FILES[@]}" 2>"$HADOLINT_STDERR") || {
    echo "WARNING: hadolint failed: $(cat "$HADOLINT_STDERR")" >&2
    rm -f "$HADOLINT_STDERR"
    echo "[]"
    exit 0
  }
  rm -f "$HADOLINT_STDERR"
fi

if [[ -z "$HADOLINT_OUTPUT" ]]; then
  echo "[]"
  exit 0
fi

# hadolint --format json emits a JSON array:
# [{"file":"Dockerfile","line":12,"column":1,"level":"error","code":"DL3008","message":"Pin versions..."}]
# Severity mapping:
#   error   -> High   (DL3xxx rule violations, syntax errors)
#   warning -> Medium
#   info, style -> Low
FINDINGS=$(echo "$HADOLINT_OUTPUT" | jq -r '
  [
    .[]? |
    {
      severity: (
        if .level == "error"   then "High"
        elif .level == "warning" then "Medium"
        else "Low"
        end
      ),
      confidence: 90,
      source: "hadolint",
      file: .file,
      line: (.line // 1),
      finding: ("\(.code): \(.message)"),
      remediation: "See https://github.com/hadolint/hadolint/wiki/\(.code)"
    }
  ]
' 2>/dev/null) || {
  echo "WARNING: hadolint output could not be parsed; hadolint findings skipped." >&2
  echo "[]"
  exit 0
}

echo "${FINDINGS:-[]}"
