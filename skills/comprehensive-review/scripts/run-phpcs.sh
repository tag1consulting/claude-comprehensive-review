#!/usr/bin/env bash
#
# run-phpcs.sh — Run phpcs (PHP_CodeSniffer) on changed PHP files and emit findings.
#
# Uses the Drupal and DrupalPractice coding standards when available via
# drupal/coder, otherwise falls back to PSR12.
#
# Usage (two forms):
#   echo "$CHANGED_FILES" | ./run-phpcs.sh          # stdin (used by SKILL.md)
#   ./run-phpcs.sh <changed_files_list>              # positional arg
#
# Output:
#   JSON array of findings in the json-findings schema.
#   Outputs "[]" if phpcs is unavailable, no PHP files changed, or no issues found.
#
# Environment:
#   PHPCS_MOCK_FILE   When set to a readable file path, read phpcs JSON
#                     output from that file instead of running the binary.
#                     For offline testing only; unset in production.

set -euo pipefail

# Accept changed files list from stdin or $1
if [[ -n "${1:-}" ]]; then
  CHANGED_FILES="$1"
else
  CHANGED_FILES=$(cat)
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: jq not installed; phpcs check skipped." >&2
  echo "[]"
  exit 0
fi

if [[ -z "${PHPCS_MOCK_FILE:-}" ]] && ! command -v phpcs >/dev/null 2>&1; then
  echo "WARNING: phpcs not installed; phpcs check skipped." >&2
  echo "[]"
  exit 0
fi

# Filter to PHP files only
PHP_FILES=()
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  case "$file" in
    *.php|*.module|*.inc|*.theme|*.install|*.profile)
      [[ -f "$file" ]] && PHP_FILES+=("$file") ;;
  esac
done <<< "$CHANGED_FILES"

if [[ ${#PHP_FILES[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

if [[ -n "${PHPCS_MOCK_FILE:-}" ]]; then
  if [[ ! -r "$PHPCS_MOCK_FILE" ]]; then
    echo "WARNING: PHPCS_MOCK_FILE '${PHPCS_MOCK_FILE}' is not readable." >&2
    echo "[]"
    exit 0
  fi
  PHPCS_OUTPUT=$(cat "$PHPCS_MOCK_FILE")
else
  # Select standard: prefer Drupal,DrupalPractice (via drupal/coder), fall back to PSR12
  PHPCS_STANDARD="PSR12"
  if phpcs -i 2>/dev/null | grep -q "Drupal"; then
    PHPCS_STANDARD="Drupal,DrupalPractice"
  fi

  # phpcs exits 0 (clean), 1 (violations found), or 2 (config/processing error).
  PHPCS_EC=0
  PHPCS_OUTPUT=$(phpcs \
    --report=json \
    --standard="$PHPCS_STANDARD" \
    --extensions=php,module,inc,theme,install,profile \
    -q \
    "${PHP_FILES[@]}" \
    2>/dev/null) || PHPCS_EC=$?
  if [[ "$PHPCS_EC" -eq 2 ]]; then
    echo "WARNING: phpcs exited with error code 2; standard '${PHPCS_STANDARD}' may not be installed or phpcs encountered a fatal error." >&2
    echo "[]"
    exit 0
  fi
fi

if [[ -z "$PHPCS_OUTPUT" ]]; then
  echo "[]"
  exit 0
fi

# phpcs JSON structure:
# {
#   "files": {
#     "/path/to/file.php": {
#       "errors": 2, "warnings": 1,
#       "messages": [
#         {"message":"...", "source":"Drupal.Commenting.DocComment", "severity":5, "type":"ERROR", "line":10, "column":1, "fixable":false}
#       ]
#     }
#   }
# }
# Severity mapping:
#   type == "ERROR"   -> High
#   type == "WARNING" -> Medium
FINDINGS=$(echo "$PHPCS_OUTPUT" | jq -r --arg root "$PWD" '
  [
    .files // {} |
    to_entries[] |
    . as $entry |
    .value.messages[]? |
    {
      severity: (if .type == "ERROR" then "High" else "Medium" end),
      confidence: 90,
      source: "phpcs",
      file: ($entry.key | ltrimstr($root + "/")),
      line: (.line // 1),
      finding: ("\(.source): \(.message)"),
      remediation: (
        "See https://www.drupal.org/docs/develop/standards or fix with: phpcs --standard=Drupal \($entry.key)"
      )
    }
  ]
' 2>/dev/null) || {
  echo "WARNING: phpcs output could not be parsed; phpcs findings skipped." >&2
  echo "[]"
  exit 0
}

echo "${FINDINGS:-[]}"
