#!/usr/bin/env bats
# Golden tests for orchestration decisions and structural contracts.
#
# Tests deterministic orchestration behavior:
#   - Tier selection based on diff size and file count
#   - Gate decisions for known fixture diffs
#   - Required SKILL.md sections still present
#   - json-findings schema fields documented in SEVERITY.md
#   - No remote operations documented as default
#
# These tests do NOT invoke LLM agents. They validate the deterministic
# scaffolding around the agents.

bats_require_minimum_version 1.5.0

setup() {
  load test_helper
  WORK=$(mktemp -d)
  SKILL_MD="${SCRIPTS_DIR}/../SKILL.md"
  SEVERITY_MD="${SCRIPTS_DIR}/../SEVERITY.md"
  PROVIDERS_MD="${SCRIPTS_DIR}/../PROVIDERS.md"
  GATE_SCRIPT="${SCRIPTS_DIR}/evaluate-gates.sh"
}

teardown() {
  rm -rf "$WORK"
}

# ---------------------------------------------------------------------------
# SKILL.md structural integrity
# ---------------------------------------------------------------------------

@test "SKILL.md: contains all required phase headings" {
  grep -q "### Phase 0" "$SKILL_MD"
  grep -q "### Phase 1:" "$SKILL_MD" || grep -q "### Phase 1b:" "$SKILL_MD"
  grep -q "### Phase 2" "$SKILL_MD"
  grep -q "### Phase 3" "$SKILL_MD"
  grep -q "### Phase 4" "$SKILL_MD"
  grep -q "### Phase 5" "$SKILL_MD"
}

@test "SKILL.md: defines TIER variable" {
  grep -q "TIER=" "$SKILL_MD"
}

@test "SKILL.md: defines tiny-tier threshold (50 lines, 3 files)" {
  grep -q "50" "$SKILL_MD"
  grep -q "TIER=tiny" "$SKILL_MD"
}

@test "SKILL.md: --quick flag is documented" {
  grep -q "\-\-quick" "$SKILL_MD"
}

@test "SKILL.md: --output-file references Write tool" {
  grep -q "Write tool\|via the Write" "$SKILL_MD"
}

@test "SKILL.md: no-post is described as the default" {
  grep -qi "no.post.*default\|default.*no.post\|no remote posting\|no-post is the default" "$SKILL_MD"
}

@test "SKILL.md: --create-pr from default branch is refused" {
  grep -q "default branch\|refused.*create-pr\|create-pr.*refused\|refused.*default" "$SKILL_MD"
}

@test "SKILL.md: Write tool is in allowed-tools frontmatter" {
  head -10 "$SKILL_MD" | grep -q '"Write"'
}

@test "SKILL.md: delegates gate evaluation to evaluate-gates.sh" {
  grep -q "evaluate-gates.sh" "$SKILL_MD"
}

@test "SKILL.md: defines DOCS_ONLY auto-cheap routing variable" {
  grep -q "DOCS_ONLY=true\|DOCS_ONLY=false" "$SKILL_MD"
}

@test "SKILL.md: defines LOW_RISK_CONFIG auto-cheap routing variable" {
  grep -q "LOW_RISK_CONFIG=true\|LOW_RISK_CONFIG=false" "$SKILL_MD"
}

@test "SKILL.md: Phase 5 reports DOCS_ONLY auto-cheap reason" {
  grep -q "Auto-cheap: DOCS_ONLY" "$SKILL_MD"
}

@test "SKILL.md: Phase 5 reports LOW_RISK_CONFIG auto-cheap reason" {
  grep -q "Auto-cheap: LOW_RISK_CONFIG" "$SKILL_MD"
}

@test "SKILL.md: novelty pass defined and only applies to Low/Medium findings" {
  grep -q "Novelty pass\|NOVELTY_DEMOTED_COUNT\|novelty candidate\|recurring" "$SKILL_MD"
  # Critical and High must be explicitly protected
  grep -q "never.*Critical.*High\|Critical.*High.*never" "$SKILL_MD"
}

@test "SKILL.md: novelty pass skipped when --no-mem or insufficient prior reviews" {
  grep -q "no-mem\|no.mem" "$SKILL_MD"
  grep -q "fewer than 2 prior review\|insufficient\|skip.*novelty" "$SKILL_MD"
}

# ---------------------------------------------------------------------------
# SEVERITY.md: json-findings contract documented
# ---------------------------------------------------------------------------

@test "SEVERITY.md: category field listed in json-findings contract" {
  grep -q "category" "$SEVERITY_MD"
}

@test "SEVERITY.md: all taxonomy values documented" {
  grep -q "authz" "$SEVERITY_MD"
  grep -q "injection" "$SEVERITY_MD"
  grep -q "dependency-cve" "$SEVERITY_MD"
  grep -q "secret" "$SEVERITY_MD"
  grep -q "architecture-coupling" "$SEVERITY_MD"
  grep -q "edge-case" "$SEVERITY_MD"
}

# ---------------------------------------------------------------------------
# PROVIDERS.md: correct GitHub inline review mechanism
# ---------------------------------------------------------------------------

@test "PROVIDERS.md: GitHub inline review uses gh api, not mcp tool" {
  grep -q "gh api" "$PROVIDERS_MD"
  ! grep -q "mcp__github-pat__" "$PROVIDERS_MD"
}

@test "PROVIDERS.md: fetch PR/MR metadata includes body field for all providers" {
  grep -q "body" "$PROVIDERS_MD"
  # GitHub
  grep -q "gh pr view.*body\|--json.*body" "$PROVIDERS_MD"
  # GitLab maps description
  grep -q "description.*body\|description→body" "$PROVIDERS_MD"
  # Bitbucket
  grep -q "description.*body\|description→body" "$PROVIDERS_MD"
}

# ---------------------------------------------------------------------------
# Gate decisions for synthetic fixture diffs
# ---------------------------------------------------------------------------

@test "gates: tiny docs-only diff: GATE_CODE_OR_INFRA=false, all security gates false" {
  printf '+Updated docs\n+More content\n' > "${WORK}/docs.diff"
  DIFF_FILE="${WORK}/docs.diff" DIFF_PATHS="README.md" \
    run bash "$GATE_SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "GATE_CODE_OR_INFRA=false"
  echo "$output" | grep -q "GATE_SECURITY_PATTERNS=false"
  echo "$output" | grep -q "GATE_ERROR_PATTERNS=false"
}

@test "gates: Go source with error handling: GATE_ERROR_PATTERNS=true, GATE_CODE_OR_INFRA=true" {
  printf '+if err != nil { return err }\n+func main() {}\n' > "${WORK}/go.diff"
  DIFF_FILE="${WORK}/go.diff" DIFF_PATHS="cmd/main.go" \
    run bash "$GATE_SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "GATE_ERROR_PATTERNS=true"
  echo "$output" | grep -q "GATE_CODE_OR_INFRA=true"
}

@test "gates: dep manifest change triggers GATE_SECURITY_PATTERNS" {
  printf '+  "lodash": "4.17.21"\n' > "${WORK}/pkg.diff"
  DIFF_FILE="${WORK}/pkg.diff" DIFF_PATHS="package.json" \
    run bash "$GATE_SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "GATE_SECURITY_PATTERNS=true"
}

@test "gates: GitHub Actions workflow triggers GATE_CODE_OR_INFRA even if diff is docs-like" {
  printf '+    runs-on: ubuntu-latest\n' > "${WORK}/ci.diff"
  DIFF_FILE="${WORK}/ci.diff" DIFF_PATHS=".github/workflows/ci.yml" \
    run bash "$GATE_SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "GATE_CODE_OR_INFRA=true"
}

# ---------------------------------------------------------------------------
# run-cve-check.sh: category field present in output
# ---------------------------------------------------------------------------

@test "cve-check: findings include category=dependency-cve" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"
  # Must be named exactly 'go.mod' — the script matches on basename.
  cp "${FIXTURES_DIR}/cve/go.mod.replace-before-require" "${WORK}/go.mod"
  OSV_MOCK_FILE="${FIXTURES_DIR}/cve/osv-batch-critical.json" \
    run --separate-stderr bash "${SCRIPTS_DIR}/run-cve-check.sh" "${WORK}/go.mod"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].category == "dependency-cve"' >/dev/null
}
