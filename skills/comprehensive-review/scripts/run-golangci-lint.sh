#!/usr/bin/env bash
#
# run-golangci-lint.sh — Run golangci-lint on changed Go files and emit findings.
#
# Usage (two forms):
#   echo "$CHANGED_FILES" | ./run-golangci-lint.sh        # stdin (used by SKILL.md)
#   ./run-golangci-lint.sh <changed_files_list>            # positional arg
#
# Output:
#   JSON array of findings in the json-findings schema.
#   Outputs "[]" if golangci-lint is unavailable, no Go files changed, or no issues found.
#
# Environment:
#   GOLANGCI_MOCK_FILE   When set to a readable file path, read golangci-lint
#                        JSON output from that file instead of running the binary.
#                        For offline testing only; unset in production.

set -euo pipefail

# Accept changed files list from stdin or $1
if [[ -n "${1:-}" ]]; then
  CHANGED_FILES="$1"
else
  CHANGED_FILES=$(cat)
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: jq not installed; golangci-lint check skipped." >&2
  echo "[]"
  exit 0
fi

if [[ -z "${GOLANGCI_MOCK_FILE:-}" ]] && ! command -v golangci-lint >/dev/null 2>&1; then
  echo "WARNING: golangci-lint not installed; golangci-lint check skipped." >&2
  echo "[]"
  exit 0
fi

# Filter to Go source files
GO_FILES=()
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  case "$file" in
    *.go) [[ -f "$file" ]] && GO_FILES+=("$file") ;;
  esac
done <<< "$CHANGED_FILES"

if [[ ${#GO_FILES[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

# Run golangci-lint (or read mock).
# --out-format=json --issues-exit-code=0 ensures JSON output even when issues exist.
if [[ -n "${GOLANGCI_MOCK_FILE:-}" ]]; then
  if [[ ! -r "$GOLANGCI_MOCK_FILE" ]]; then
    echo "WARNING: GOLANGCI_MOCK_FILE '${GOLANGCI_MOCK_FILE}' is not readable." >&2
    echo "[]"
    exit 0
  fi
  GL_OUTPUT=$(cat "$GOLANGCI_MOCK_FILE")
else
  # golangci-lint must run from the Go module root (where go.mod lives).
  # Walk up from the first changed file's directory.
  MODULE_ROOT=""
  _dir=$(dirname "${GO_FILES[0]}")
  while true; do
    if [[ -f "$_dir/go.mod" ]]; then
      MODULE_ROOT="$_dir"
      break
    fi
    [[ "$_dir" == "/" || "$_dir" == "." ]] && break
    _dir=$(dirname "$_dir")
  done
  # Final check: CWD itself
  if [[ -z "$MODULE_ROOT" && -f "go.mod" ]]; then
    MODULE_ROOT="."
  fi
  if [[ -z "$MODULE_ROOT" ]]; then
    echo "WARNING: could not find go.mod — golangci-lint check skipped." >&2
    echo "[]"
    exit 0
  fi

  # Derive unique package directories relative to the module root
  PKG_PATTERNS=()
  declare -A _seen_dirs
  for f in "${GO_FILES[@]}"; do
    d=$(dirname "$f")
    if [[ "$MODULE_ROOT" == "." ]]; then
      rel_d="$d"
    else
      rel_d="${d#"${MODULE_ROOT}/"}"
      [[ "$rel_d" == "$d" ]] && rel_d="."
    fi
    if [[ -z "${_seen_dirs[$rel_d]+x}" ]]; then
      _seen_dirs[$rel_d]=1
      PKG_PATTERNS+=("./${rel_d}/...")
    fi
  done

  GOLANGCI_STDERR=$(mktemp)
  trap 'rm -f "$GOLANGCI_STDERR"' EXIT
  GL_OUTPUT=$(cd "$MODULE_ROOT" && golangci-lint run --out-format=json --issues-exit-code=0 "${PKG_PATTERNS[@]}" 2>"$GOLANGCI_STDERR") || true
  if [[ -z "$GL_OUTPUT" ]]; then
    echo "WARNING: golangci-lint produced no output. stderr: $(cat "$GOLANGCI_STDERR")" >&2
    echo "[]"
    exit 0
  fi
fi

if [[ -z "$GL_OUTPUT" ]]; then
  echo "[]"
  exit 0
fi

# golangci-lint reports Pos.Filename relative to the module root.
# Prepend MODULE_ROOT so the path matches git-relative paths.
FILE_PREFIX=""
if [[ -n "${MODULE_ROOT:-}" && "$MODULE_ROOT" != "." ]]; then
  FILE_PREFIX="${MODULE_ROOT}/"
fi

# Convert golangci-lint JSON to the findings schema.
# Severity mapping by linter name:
#   errcheck, govet, staticcheck → High
#   everything else               → Medium
FINDINGS=$(echo "$GL_OUTPUT" | jq -r --arg prefix "$FILE_PREFIX" '
  [
    .Issues[]? |
    {
      severity: (
        if (.FromLinter == "errcheck" or .FromLinter == "govet" or .FromLinter == "staticcheck")
        then "High"
        else "Medium"
        end
      ),
      confidence: 90,
      source: "golangci-lint",
      file: ($prefix + .Pos.Filename),
      line: .Pos.Line,
      finding: ("\(.FromLinter): \(.Text)"),
      remediation: "Review the \(.FromLinter) linter documentation for this issue."
    }
  ]
' 2>/dev/null) || {
  echo "WARNING: golangci-lint output could not be parsed; golangci-lint findings skipped." >&2
  echo "[]"
  exit 0
}

echo "${FINDINGS:-[]}"
