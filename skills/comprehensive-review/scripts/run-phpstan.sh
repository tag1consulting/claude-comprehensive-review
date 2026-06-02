#!/usr/bin/env bash
#
# run-phpstan.sh — Run PHPStan on changed PHP files and emit findings.
#
# Uses phpstan-drupal extension when available. Runs at level 3 by default
# (balances coverage vs noise on mixed legacy/modern Drupal code); consumers
# can override via PHPSTAN_LEVEL env var or a phpstan.neon in the repo root.
#
# Usage (two forms):
#   echo "$CHANGED_FILES" | ./run-phpstan.sh         # stdin (used by SKILL.md)
#   ./run-phpstan.sh <changed_files_list>             # positional arg
#
# Output:
#   JSON array of findings in the json-findings schema.
#   Outputs "[]" if phpstan is unavailable, no PHP files changed, or no issues found.
#
# Environment:
#   PHPSTAN_MOCK_FILE   When set to a readable file path, read phpstan JSON
#                       output from that file instead of running the binary.
#                       For offline testing only; unset in production.
#   PHPSTAN_LEVEL       Analysis level 0-9 (default: 3). Ignored when the repo
#                       provides its own phpstan.neon or phpstan.neon.dist.

set -euo pipefail

# Accept changed files list from stdin or $1
if [[ -n "${1:-}" ]]; then
  CHANGED_FILES="$1"
else
  CHANGED_FILES=$(cat)
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: jq not installed; phpstan check skipped." >&2
  echo "[]"
  exit 0
fi

if [[ -z "${PHPSTAN_MOCK_FILE:-}" ]] && ! command -v phpstan >/dev/null 2>&1; then
  echo "WARNING: phpstan not installed; phpstan check skipped." >&2
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

if [[ -n "${PHPSTAN_MOCK_FILE:-}" ]]; then
  if [[ ! -r "$PHPSTAN_MOCK_FILE" ]]; then
    echo "WARNING: PHPSTAN_MOCK_FILE '${PHPSTAN_MOCK_FILE}' is not readable." >&2
    echo "[]"
    exit 0
  fi
  PHPSTAN_OUTPUT=$(cat "$PHPSTAN_MOCK_FILE")
else
  # Determine level: honour env var, fall back to 3
  LEVEL="${PHPSTAN_LEVEL:-3}"
  if ! [[ "$LEVEL" =~ ^[0-9]$ ]]; then
    echo "WARNING: PHPSTAN_LEVEL='${LEVEL}' is not a valid level (0-9); using 3." >&2
    LEVEL=3
  fi

  # Build phpstan args: use consumer config if present, else pass --level
  PHPSTAN_ARGS=(analyse --error-format=json --no-progress --memory-limit=512M)
  if [[ -f "phpstan.neon" ]] || [[ -f "phpstan.neon.dist" ]]; then
    # Consumer config drives everything — don't add --level or --autoload-file
    :
  else
    PHPSTAN_ARGS+=(--level="$LEVEL")
    # Auto-include phpstan-drupal bootstrap stub if the extension is available.
    # A file-exists check avoids the 2-5s composer subprocess (which may also
    # touch the network) — the result is deterministic per commit anyway.
    # Also verify vendor/autoload.php actually exists: passing a nonexistent
    # autoload file would make phpstan hard-fail into the exit-code->=2 branch,
    # which masks a broken install as "no findings".
    # Resolve vendor paths relative to repo root, not script CWD
    REPO_ROOT="${GITHUB_WORKSPACE:-$PWD}"
    if [[ -d "${REPO_ROOT}/vendor/mglaman/phpstan-drupal" ]] && [[ -f "${REPO_ROOT}/vendor/autoload.php" ]]; then
      PHPSTAN_ARGS+=(--autoload-file="${REPO_ROOT}/vendor/autoload.php")
    fi
  fi

  PHPSTAN_ARGS+=("${PHP_FILES[@]}")

  # phpstan exits 1 when errors found (expected); exit >=2 indicates a real error.
  PHPSTAN_EC=0
  PHPSTAN_OUTPUT=$(phpstan "${PHPSTAN_ARGS[@]}" 2>/dev/null) || PHPSTAN_EC=$?
  if [[ "$PHPSTAN_EC" -ge 2 ]]; then
    echo "WARNING: phpstan exited with error code ${PHPSTAN_EC}; phpstan may not be configured correctly." >&2
    echo "[]"
    exit 0
  fi
fi

if [[ -z "$PHPSTAN_OUTPUT" ]]; then
  echo "[]"
  exit 0
fi

# PHPStan JSON structure:
# {
#   "totals": {"errors": 1, "file_errors": 1},
#   "files": {
#     "/path/file.php": {
#       "errors": 1,
#       "messages": [
#         {"message": "...", "line": 42, "ignorable": true}
#       ]
#     }
#   },
#   "errors": []
# }
# PHPStan has no severity field — all findings are errors; map to High.
FINDINGS=$(echo "$PHPSTAN_OUTPUT" | jq -r --arg root "$PWD" '
  [
    .files // {} |
    to_entries[] |
    . as $entry |
    .value.messages[]? |
    select(.message != null) |
    {
      severity: "High",
      confidence: 85,
      source: "phpstan",
      file: ($entry.key | ltrimstr($root + "/")),
      line: (.line // 1),
      finding: .message,
      remediation: "Fix the type error reported by PHPStan. See https://phpstan.org/user-guide/getting-started"
    }
  ]
' 2>/dev/null) || {
  echo "WARNING: phpstan output could not be parsed; phpstan findings skipped." >&2
  echo "[]"
  exit 0
}

echo "${FINDINGS:-[]}"
