#!/usr/bin/env bash
#
# run-eslint.sh — Run ESLint on changed JS/TS files and emit findings.
#
# Requires that the consuming repository already has ESLint configured
# (eslint.config.* or .eslintrc.*) and accessible via `npx eslint` or a
# locally-installed `./node_modules/.bin/eslint`. The script is a no-op if
# no ESLint config is found, so consumers without JS/TS code are unaffected.
#
# Usage (two forms):
#   echo "$CHANGED_FILES" | ./run-eslint.sh        # stdin (used by SKILL.md)
#   ./run-eslint.sh <changed_files_list>            # positional arg
#
# Output:
#   JSON array of findings in the json-findings schema.
#   Outputs "[]" if ESLint is unavailable, no config found, no JS/TS files
#   changed, or no issues found.
#
# Environment:
#   ESLINT_MOCK_FILE   When set to a readable file path, read ESLint JSON
#                      output from that file instead of running the binary.
#                      For offline testing only; unset in production.

set -euo pipefail

# Accept changed files list from stdin or $1
if [[ -n "${1:-}" ]]; then
  CHANGED_FILES="$1"
else
  CHANGED_FILES=$(cat)
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: jq not installed; eslint check skipped." >&2
  echo "[]"
  exit 0
fi

# Resolve eslint binary: prefer local node_modules, fall back to npx
ESLINT_BIN=()
ESLINT_SUPPORTS_NO_WARN_IGNORED=false
if [[ -z "${ESLINT_MOCK_FILE:-}" ]]; then
  if [[ -x "./node_modules/.bin/eslint" ]]; then
    ESLINT_BIN=("./node_modules/.bin/eslint")
  elif command -v npx >/dev/null 2>&1 && npx --no eslint --version >/dev/null 2>&1; then
    ESLINT_BIN=("npx" "eslint")
  else
    echo "WARNING: eslint not found (tried node_modules/.bin/eslint and npx); eslint check skipped." >&2
    echo "[]"
    exit 0
  fi

  # --no-warn-ignored was added in ESLint 8.x; guard against older versions by
  # inspecting --help output, which is more reliable than probing with --version
  # (--version short-circuits arg parsing and can return 0 regardless of the flag).
  if "${ESLINT_BIN[@]}" --help 2>&1 | grep -q -- '--no-warn-ignored'; then
    ESLINT_SUPPORTS_NO_WARN_IGNORED=true
  fi

  # Only run if a config file is present — avoids polluting repos without ESLint.
  # Use GITHUB_WORKSPACE (repo root in CI) as primary; fall back to PWD for local runs.
  ESLINT_CONFIG_FOUND=false
  SEARCH_DIRS=("${GITHUB_WORKSPACE:-$PWD}")
  [[ -n "${GITHUB_WORKSPACE:-}" && "$GITHUB_WORKSPACE" != "$PWD" ]] && SEARCH_DIRS+=("$PWD")
  for cfg in eslint.config.js eslint.config.mjs eslint.config.cjs \
             .eslintrc.js .eslintrc.cjs .eslintrc.yaml .eslintrc.yml .eslintrc.json .eslintrc; do
    for dir in "${SEARCH_DIRS[@]}"; do
      [[ -f "$dir/$cfg" ]] && { ESLINT_CONFIG_FOUND=true; break 2; }
    done
  done
  if [[ "$ESLINT_CONFIG_FOUND" == "false" ]]; then
    echo "[]"
    exit 0
  fi
fi

# Filter to JS/TS files only
JS_FILES=()
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  case "$file" in
    *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs)
      [[ -f "$file" ]] && JS_FILES+=("$file") ;;
  esac
done <<< "$CHANGED_FILES"

if [[ ${#JS_FILES[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

if [[ -n "${ESLINT_MOCK_FILE:-}" ]]; then
  if [[ ! -r "$ESLINT_MOCK_FILE" ]]; then
    echo "WARNING: ESLINT_MOCK_FILE '${ESLINT_MOCK_FILE}' is not readable." >&2
    echo "[]"
    exit 0
  fi
  ESLINT_OUTPUT=$(cat "$ESLINT_MOCK_FILE")
else
  # --format json; --no-warn-ignored (ESLint >=8) prevents noise on ignored paths;
  # ESLint exits 0 (clean), 1 (lint issues found), or 2 (fatal config/plugin error).
  ESLINT_EC=0
  ESLINT_EXTRA_FLAGS=()
  [[ "$ESLINT_SUPPORTS_NO_WARN_IGNORED" == "true" ]] && ESLINT_EXTRA_FLAGS+=(--no-warn-ignored)
  ESLINT_OUTPUT=$("${ESLINT_BIN[@]}" --format json "${ESLINT_EXTRA_FLAGS[@]}" "${JS_FILES[@]}" 2>/dev/null) || ESLINT_EC=$?
  if [[ "$ESLINT_EC" -eq 2 ]]; then
    echo "WARNING: eslint exited with fatal error (exit 2); broken config or missing plugin." >&2
    echo "[]"
    exit 0
  fi
fi

if [[ -z "$ESLINT_OUTPUT" ]]; then
  echo "[]"
  exit 0
fi

# ESLint JSON structure:
# [
#   {
#     "filePath": "/abs/path/file.ts",
#     "messages": [
#       {"ruleId":"no-unused-vars","severity":2,"message":"...","line":5,"column":3}
#     ]
#   }
# ]
# severity: 2 = error -> High, 1 = warning -> Medium
FINDINGS=$(echo "$ESLINT_OUTPUT" | jq -r --arg root "$PWD" '
  [
    .[]? |
    . as $file |
    .messages[]? |
    select(.ruleId != null) |
    {
      severity: (if .severity == 2 then "High" else "Medium" end),
      confidence: 90,
      source: "eslint",
      file: ($file.filePath | ltrimstr($root + "/")),
      line: (.line // 1),
      finding: ("\(.ruleId): \(.message)"),
      remediation: (
        if .ruleId then
          "See https://eslint.org/docs/rules/\(.ruleId)"
        else
          "Fix ESLint violation on this line"
        end
      )
    }
  ]
' 2>/dev/null) || {
  echo "WARNING: eslint output could not be parsed; eslint findings skipped." >&2
  echo "[]"
  exit 0
}

echo "${FINDINGS:-[]}"
