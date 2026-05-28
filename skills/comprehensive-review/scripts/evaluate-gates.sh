#!/usr/bin/env bash
#
# evaluate-gates.sh — Evaluate the four agent-dispatch gates and emit
# shell-sourceable key=value assignments to stdout.
#
# Usage:
#   source <(DIFF_FILE=<path> DIFF_PATHS=<newline-list> bash evaluate-gates.sh)
#
# Required environment:
#   DIFF_FILE   Path to the aggregate diff temp file
#   DIFF_PATHS  Newline-separated list of changed repo-relative file paths
#
# Output (sourced by the orchestrator):
#   GATE_ERROR_PATTERNS=true|false
#   GATE_CONTROL_FLOW=true|false
#   GATE_SECURITY_PATTERNS=true|false
#   GATE_CODE_OR_INFRA=true|false
#
# When DIFF_FILE is absent or DIFF_PATHS is empty, all gates default to true
# (conservative — avoids silently skipping agents due to missing data).

set -euo pipefail

DIFF_FILE="${DIFF_FILE:-}"
DIFF_PATHS="${DIFF_PATHS:-}"

if [[ -z "$DIFF_FILE" || ! -f "$DIFF_FILE" || -z "$DIFF_PATHS" ]]; then
  echo "GATE_ERROR_PATTERNS=true"
  echo "GATE_CONTROL_FLOW=true"
  echo "GATE_SECURITY_PATTERNS=true"
  echo "GATE_CODE_OR_INFRA=true"
  exit 0
fi

# Gate: has_error_patterns — fires silent-failure-hunter
# Exit 0 = match → set gate true; exit 1 = no match → leave false; exit 2 = I/O error → abort.
GATE_ERROR_PATTERNS=false
_rc=0
grep -qE 'catch\b|if err|try \{|rescue\b|Result<|unwrap\b|\.error\(|\.expect\(|runCatching|guard\b|throws\b' "$DIFF_FILE" || _rc=$?
if [[ $_rc -eq 2 ]]; then echo "ERROR: grep failed reading $DIFF_FILE" >&2; exit 1; fi
if [[ $_rc -eq 0 ]]; then GATE_ERROR_PATTERNS=true; fi

# Gate: has_control_flow — fires edge-case-hunter (added lines only via + prefix filter)
# The first grep (extract + lines) may legitimately exit 1 (no added lines); treat that as false.
# The second grep exits 2 only on I/O error, which we abort on.
GATE_CONTROL_FLOW=false
_added_lines=$(grep -E '^\+' "$DIFF_FILE" || true)
if [[ -n "$_added_lines" ]]; then
  _rc=0
  echo "$_added_lines" | grep -qE '\b(if|elif|else|for|while|do|case|switch|match|try|catch|except|rescue|unless|when|loop|break|continue|return|goto|defer|finally)\b' || _rc=$?
  if [[ $_rc -eq 2 ]]; then echo "ERROR: grep failed on added lines" >&2; exit 1; fi
  if [[ $_rc -eq 0 ]]; then GATE_CONTROL_FLOW=true; fi
fi

# Gate: has_security_patterns — fires security-reviewer even on small/medium diffs
GATE_SECURITY_PATTERNS=false
if grep -qiE 'auth|token|secret|password|crypt|hash|\bsign\b|verify|exec\b|eval\b|sql|sanitize|escape|xss|csrf|cors|header|redirect|deserialize|cookie|session|jwt|oauth|ldap|saml|rbac|acl|permission|privilege|sudo|chmod|chown|setuid|x509|tls|ssl|cert|certificate|keystore|nonce|salt|hmac|aes|rsa|ecdsa|pbkdf2|bcrypt|scrypt|curl\b|wget\b|\bsource\b|\bIFS\b|LD_PRELOAD|\$\{\{' "$DIFF_FILE"; then
  GATE_SECURITY_PATTERNS=true
fi
if echo "$DIFF_PATHS" | grep -qiE '(auth|passwords?|credentials?|tokens?|secrets?)|(^|/)(api|routes?)/|(^|/)(package\.json|package-lock\.json|go\.mod|go\.sum|composer\.json|composer\.lock|requirements[^/]*\.txt|pyproject\.toml|Pipfile(\.lock)?|Gemfile(\.lock)?|[Cc]argo\.(toml|lock)|yarn\.lock|pnpm-lock\.yaml)$|(^|/)\.env|(^|/)settings\.(py|ya?ml|json|toml)$|(^|/)(Dockerfile|Containerfile)$|\.sh$|\.bash$|(^|/)\.github/workflows/'; then
  GATE_SECURITY_PATTERNS=true
fi

# Gate: has_code_or_infra — suppresses architecture-reviewer on pure docs/meta diffs
GATE_CODE_OR_INFRA=false
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  # Workflow files always count as infra
  if echo "$f" | grep -qE '(^|/)\.github/workflows/'; then
    GATE_CODE_OR_INFRA=true; break
  fi
  # Pure doc extensions → skip
  echo "$f" | grep -qE '\.(md|markdown|txt|rst|adoc)$' && continue
  # Meta directories → skip
  echo "$f" | grep -qE '(^|/)(docs|memory-bank|\.github|\.claude)/' && continue
  # Meta filenames → skip
  echo "$f" | grep -qiE '(^|/)(CHANGELOG|README|LICENSE|NOTICE|AUTHORS|CONTRIBUTING|CODEOWNERS|CODE_OF_CONDUCT)(\..+)?$' && continue
  # Anything else is code or infra
  GATE_CODE_OR_INFRA=true; break
done <<< "$DIFF_PATHS"

echo "GATE_ERROR_PATTERNS=${GATE_ERROR_PATTERNS}"
echo "GATE_CONTROL_FLOW=${GATE_CONTROL_FLOW}"
echo "GATE_SECURITY_PATTERNS=${GATE_SECURITY_PATTERNS}"
echo "GATE_CODE_OR_INFRA=${GATE_CODE_OR_INFRA}"
