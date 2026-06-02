#!/usr/bin/env bash
#
# run-kube-linter.sh — Run kube-linter on changed Kubernetes manifest files.
#
# Triggers on YAML/JSON files that contain Kubernetes apiVersion + kind fields.
# Catches reliability issues (missing liveness probes, resource limits, :latest
# image tags) that checkov's CIS-benchmark focus misses.
#
# Usage (two forms):
#   echo "$CHANGED_FILES" | ./run-kube-linter.sh    # stdin (used by SKILL.md)
#   ./run-kube-linter.sh <changed_files_list>        # positional arg
#
# Output:
#   JSON array of findings in the json-findings schema.
#   Outputs "[]" if kube-linter is unavailable, no K8s files changed, or no issues found.
#
# Environment:
#   KUBELINTER_MOCK_FILE   When set to a readable file path, read kube-linter
#                          JSON output from that file instead of running the binary.
#                          For offline testing only; unset in production.

set -euo pipefail

# Accept changed files list from stdin or $1
if [[ -n "${1:-}" ]]; then
  CHANGED_FILES="$1"
else
  CHANGED_FILES=$(cat)
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: jq not installed; kube-linter check skipped." >&2
  echo "[]"
  exit 0
fi

if [[ -z "${KUBELINTER_MOCK_FILE:-}" ]] && ! command -v kube-linter >/dev/null 2>&1; then
  echo "WARNING: kube-linter not installed; kube-linter check skipped." >&2
  echo "[]"
  exit 0
fi

# Filter to YAML/JSON files that look like Kubernetes manifests (apiVersion + kind)
K8S_FILES=()
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  [[ -f "$file" ]] || continue
  case "$file" in
    *.yaml|*.yml)
      # YAML K8s heuristic: apiVersion: and kind: as top-level keys
      if grep -qE '^apiVersion:' "$file" 2>/dev/null && grep -qE '^kind:' "$file" 2>/dev/null; then
        K8S_FILES+=("$file")
      fi
      ;;
    *.json)
      # JSON K8s heuristic: "apiVersion": and "kind": as object keys
      if grep -qE '"apiVersion"\s*:' "$file" 2>/dev/null && grep -qE '"kind"\s*:' "$file" 2>/dev/null; then
        K8S_FILES+=("$file")
      fi
      ;;
  esac
done <<< "$CHANGED_FILES"

if [[ ${#K8S_FILES[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

if [[ -n "${KUBELINTER_MOCK_FILE:-}" ]]; then
  if [[ ! -r "$KUBELINTER_MOCK_FILE" ]]; then
    echo "WARNING: KUBELINTER_MOCK_FILE '${KUBELINTER_MOCK_FILE}' is not readable." >&2
    echo "[]"
    exit 0
  fi
  KUBELINTER_OUTPUT=$(cat "$KUBELINTER_MOCK_FILE")
else
  # kube-linter exits 1 when violations found (expected); capture stderr to
  # distinguish genuine errors from a no-violations run.
  KUBELINTER_STDERR=$(mktemp)
  KUBELINTER_OUTPUT=$(kube-linter lint --format json "${K8S_FILES[@]}" 2>"$KUBELINTER_STDERR") || true
  if [[ -z "$KUBELINTER_OUTPUT" ]] && [[ -s "$KUBELINTER_STDERR" ]]; then
    echo "WARNING: kube-linter failed: $(cat "$KUBELINTER_STDERR")" >&2
  fi
  rm -f "$KUBELINTER_STDERR"
fi

if [[ -z "$KUBELINTER_OUTPUT" ]]; then
  echo "[]"
  exit 0
fi

# kube-linter JSON structure:
# {
#   "Reports": [
#     {
#       "Diagnostic": {"Message": "..."},
#       "Check": "no-read-only-root-fs",
#       "Remediation": "...",
#       "Object": {
#         "Metadata": {"FilePath": "deploy.yaml", "LineNumber": 1},
#         "Type": {"Group":"apps","Version":"v1","Kind":"Deployment"},
#         "Name": "my-app"
#       }
#     }
#   ],
#   "Summary": {"ChecksStatus": "FAILED"}
# }
# kube-linter has no severity field; map all findings to Medium (reliability,
# not security — security issues are better caught by checkov).
FINDINGS=$(echo "$KUBELINTER_OUTPUT" | jq -r '
  [
    .Reports[]? |
    {
      severity: "Medium",
      confidence: 85,
      source: "kube-linter",
      file: (.Object.Metadata.FilePath // "unknown"),
      line: (.Object.Metadata.LineNumber // 1),
      finding: ("\(.Check): \(.Diagnostic.Message // "policy violation") [\(.Object.Type.Kind // "resource") \(.Object.Name // "")]"),
      remediation: (.Remediation // "See https://docs.kubelinter.io/#/generated/checks")
    }
  ]
' 2>/dev/null) || {
  echo "WARNING: kube-linter output could not be parsed; kube-linter findings skipped." >&2
  echo "[]"
  exit 0
}

echo "${FINDINGS:-[]}"
