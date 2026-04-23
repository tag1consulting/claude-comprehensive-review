#!/usr/bin/env bash
#
# run-trufflehog.sh — Run trufflehog on changed files and emit findings.
#
# Usage:
#   ./run-trufflehog.sh <diff_file_or_changed_files_list>
#
# When $1 is a file that exists on disk, trufflehog is run against that file
# (diff-scanning mode — the path is passed as a single argument).
# Otherwise $1 (or stdin if $1 is absent) is treated as a newline-separated
# list of changed file paths (per-file filesystem scanning mode).
#
# Output:
#   JSON array of findings in the json-findings schema.
#   Outputs "[]" if trufflehog is unavailable or no secrets found.
#
# Environment:
#   TRUFFLEHOG_MOCK_FILE  When set to a readable file path, read trufflehog
#                         JSON output from that file instead of running the
#                         binary. For offline testing only; unset in production.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: jq not installed; trufflehog check skipped." >&2
  echo "[]"
  exit 0
fi

if [[ -z "${TRUFFLEHOG_MOCK_FILE:-}" ]] && ! command -v trufflehog >/dev/null 2>&1; then
  echo "WARNING: trufflehog not installed; trufflehog check skipped." >&2
  echo "[]"
  exit 0
fi

# jq filter to convert trufflehog NDJSON into findings array
_th_transform() {
  jq -Rs '
    split("\n") | map(select(length > 0)) |
    map(
      (. | fromjson? // null) |
      select(. != null) |
      {
        severity: (if .Verified then "Critical" else "High" end),
        confidence: (if .Verified then 95 else 85 end),
        source: "trufflehog",
        file: (.SourceMetadata.Data.Filesystem.file? // "unknown"),
        line: (.SourceMetadata.Data.Filesystem.line? // 0),
        finding: ("Potential secret detected: \(.DetectorName) (\(if .Verified then "verified" else "unverified" end))"),
        remediation: "Rotate the credential immediately and remove it from the repository history."
      }
    )
  '
}

# Mock path
if [[ -n "${TRUFFLEHOG_MOCK_FILE:-}" ]]; then
  if [[ ! -r "$TRUFFLEHOG_MOCK_FILE" ]]; then
    echo "WARNING: TRUFFLEHOG_MOCK_FILE '${TRUFFLEHOG_MOCK_FILE}' is not readable." >&2
    echo "[]"
    exit 0
  fi
  FINDINGS=$(cat "$TRUFFLEHOG_MOCK_FILE" | _th_transform 2>/dev/null) || {
    echo "WARNING: TRUFFLEHOG_MOCK_FILE could not be parsed." >&2
    echo "[]"
    exit 0
  }
  echo "${FINDINGS:-[]}"
  exit 0
fi

# Determine scan mode: if $1 names an existing file, scan it directly (diff mode).
# Otherwise treat $1 (or stdin) as a newline-separated changed-files list.
if [[ -n "${1:-}" && -f "$1" ]]; then
  # Diff-file mode (called as: run-trufflehog.sh "$DIFF_FILE")
  TH_OUTPUT=$(trufflehog filesystem --json --no-update "$1" 2>/dev/null || true)
  if [[ -z "$TH_OUTPUT" ]]; then
    echo "[]"
    exit 0
  fi
  FINDINGS=$(echo "$TH_OUTPUT" | _th_transform 2>/dev/null) || {
    echo "WARNING: trufflehog output could not be parsed." >&2
    echo "[]"
    exit 0
  }
  echo "${FINDINGS:-[]}"
  exit 0
fi

# Changed-files list mode: accept from $1 or stdin
if [[ -n "${1:-}" ]]; then
  CHANGED_FILES="$1"
else
  CHANGED_FILES=$(cat)
fi

TARGET_FILES=()
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  [[ -f "$file" ]] && TARGET_FILES+=("$file")
done <<< "$CHANGED_FILES"

if [[ ${#TARGET_FILES[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

# Run trufflehog once per file, collect arrays, merge at the end
FILE_ARRAYS=()
for file in "${TARGET_FILES[@]}"; do
  TH_OUTPUT=$(trufflehog filesystem --json --no-update "$file" 2>/dev/null || true)
  [[ -z "$TH_OUTPUT" ]] && continue

  FILE_FINDINGS=$(echo "$TH_OUTPUT" | _th_transform 2>/dev/null) || {
    echo "WARNING: trufflehog output for ${file} could not be parsed; skipping." >&2
    continue
  }
  FILE_ARRAYS+=("$FILE_FINDINGS")
done

if [[ ${#FILE_ARRAYS[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

printf '%s\n' "${FILE_ARRAYS[@]}" | jq -s 'add // []'
