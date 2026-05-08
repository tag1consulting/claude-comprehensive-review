#!/usr/bin/env bash
#
# run-checkov.sh — Run checkov on changed IaC files and emit findings.
#
# Covers: Terraform (*.tf, *.tfvars), Kubernetes/Helm YAML, Dockerfiles,
# CloudFormation JSON/YAML, Azure ARM templates.
#
# Usage:
#   ./run-checkov.sh <changed_files_list>
#   echo "file1\nfile2" | ./run-checkov.sh
#
# When $1 is provided, it is treated as a newline-separated list of changed
# file paths. When absent, the list is read from stdin.
#
# Output:
#   JSON array of findings in the json-findings schema.
#   Outputs "[]" if checkov is unavailable, no IaC files changed, or no issues found.
#
# Environment:
#   CHECKOV_MOCK_FILE   When set to a readable file path, read checkov JSON
#                       output from that file instead of running the binary.
#                       For offline testing only; unset in production.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: jq not installed; checkov check skipped." >&2
  echo "[]"
  exit 0
fi

if [[ -z "${CHECKOV_MOCK_FILE:-}" ]] && ! command -v checkov >/dev/null 2>&1; then
  echo "WARNING: checkov not installed; checkov check skipped." >&2
  echo "[]"
  exit 0
fi

# Accept changed-files list from $1 or stdin
if [[ -n "${1:-}" ]]; then
  CHANGED_FILES="$1"
else
  CHANGED_FILES=$(cat)
fi

# Collect IaC files that exist on disk.
#
# Terraform (.tf, .tfvars) and Dockerfiles are unambiguous — always accept.
# YAML and JSON are ambiguous (the majority of .yaml/.yml/.json files in a
# typical repo are not IaC). Without a content sniff, checkov spins up Python
# and loads its policy library (~3-8s cold start) just to find nothing.
# Require a telltale IaC header before accepting these files:
#   * k8s / Helm manifests: top-level "apiVersion:" AND "kind:"
#   * CloudFormation (YAML or JSON): "AWSTemplateFormatVersion"
#   * Azure ARM templates (YAML or JSON): "$schema" referencing schema.management.azure.com
#
# Deliberately NOT scanned:
#   * GitHub Actions workflows (better served by actionlint)
#   * Serverless Framework (serverless.yml)
#   * Helm Chart.yaml (has apiVersion but no kind)
IAC_FILES=()
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  [[ -f "$file" ]] || continue
  case "$file" in
    *.tf|*.tfvars)
      IAC_FILES+=("$file") ;;
    Dockerfile|*/Dockerfile|Dockerfile.*|*/Dockerfile.*|*.dockerfile)
      IAC_FILES+=("$file") ;;
    *.yaml|*.yml)
      # k8s sniff: apiVersion must match a k8s-shaped value — either bare
      # "v<N>" (core API group) or "<group>/v<N>[alpha|beta<N>]" (named group).
      # Plus kind must be present. Uses POSIX ERE (no backreferences).
      if grep -qE '^[[:space:]]*AWSTemplateFormatVersion:' "$file" 2>/dev/null \
         || grep -qE 'schema\.management\.azure\.com' "$file" 2>/dev/null \
         || { grep -qE '^[[:space:]]*apiVersion:[[:space:]]*(([a-z0-9][-a-z0-9.]*/)?v[0-9]+(alpha[0-9]+|beta[0-9]+)?|"([a-z0-9][-a-z0-9.]*/)?v[0-9]+(alpha[0-9]+|beta[0-9]+)?")[[:space:]]*$' "$file" 2>/dev/null \
              && grep -qE '^[[:space:]]*kind:' "$file" 2>/dev/null; }; then
        IAC_FILES+=("$file")
      fi ;;
    *.json)
      # CloudFormation: "AWSTemplateFormatVersion": "..."
      # Azure ARM: "$schema": "https://schema.management.azure.com/..."
      # Anchor on JSON key shape to avoid matching dependency names or doc fixtures.
      # shellcheck disable=SC2016  # $schema is a literal JSON key, not a shell var
      if grep -qE '"AWSTemplateFormatVersion"[[:space:]]*:' "$file" 2>/dev/null \
         || grep -qE '"\$schema"[[:space:]]*:[[:space:]]*"[^"]*schema\.management\.azure\.com' "$file" 2>/dev/null; then
        IAC_FILES+=("$file")
      fi ;;
  esac
done <<< "$CHANGED_FILES"

if [[ ${#IAC_FILES[@]} -eq 0 ]]; then
  echo "[]"
  exit 0
fi

if [[ -n "${CHECKOV_MOCK_FILE:-}" ]]; then
  if [[ ! -r "$CHECKOV_MOCK_FILE" ]]; then
    echo "WARNING: CHECKOV_MOCK_FILE '${CHECKOV_MOCK_FILE}' is not readable." >&2
    echo "[]"
    exit 0
  fi
  CHECKOV_OUTPUT=$(cat "$CHECKOV_MOCK_FILE")
else
  # Build --file arg list: checkov accepts repeated --file flags
  CHECKOV_FILE_ARGS=()
  for f in "${IAC_FILES[@]}"; do
    CHECKOV_FILE_ARGS+=(--file "$f")
  done

  # checkov exits 1 when findings are found (expected); exit >=2 indicates error.
  CHECKOV_EC=0
  CHECKOV_OUTPUT=$(checkov \
    "${CHECKOV_FILE_ARGS[@]}" \
    --output json \
    --quiet \
    --compact \
    2>/dev/null) || CHECKOV_EC=$?
  if [[ "$CHECKOV_EC" -ge 2 ]]; then
    echo "WARNING: checkov exited with error code ${CHECKOV_EC}; checkov may not be installed correctly." >&2
    echo "[]"
    exit 0
  fi

  if [[ -z "$CHECKOV_OUTPUT" ]]; then
    echo "[]"
    exit 0
  fi
fi

if [[ -z "$CHECKOV_OUTPUT" ]]; then
  echo "[]"
  exit 0
fi

# checkov JSON can be a single object or an array of objects (one per framework).
# Normalise to an array, extract failed_checks, project to findings schema.
# Severity mapping: CKV2_* (v2 rules) and CKV_SECRET_* (secret detection) -> High
# All other checks -> Medium. Confidence: 80 (static analysis without runtime context).
FINDINGS=$(echo "$CHECKOV_OUTPUT" | jq -r '
  (if type == "array" then . else [.] end) |
  [
    .[].results?.failed_checks[]? |
    {
      severity: (
        if (.check_id | test("^(CKV2_|CKV_SECRET_)")) then "High"
        else "Medium"
        end
      ),
      confidence: 80,
      source: "checkov",
      file: (.repo_file_path | ltrimstr("/")),
      line: (.file_line_range[0] // 1),
      finding: ("\(.check_id): \(.check_id_name // .resource // "policy violation")"),
      remediation: (
        if .guideline and (.guideline | length > 0) then .guideline
        else "See https://docs.prismacloud.io/en/enterprise-edition/policy-reference"
        end
      )
    }
  ]
' 2>/dev/null) || {
  echo "WARNING: checkov output could not be parsed; checkov findings skipped." >&2
  echo "[]"
  exit 0
}

echo "${FINDINGS:-[]}"
