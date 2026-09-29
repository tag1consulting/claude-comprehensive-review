#!/usr/bin/env bats
# Regression tests for Claude Code's positional-argument substitution.
#
# The harness replaces $0..$9 (0-indexed) anywhere in a SKILL.md body, including
# inside bash code fences, whenever that argument index was supplied. A literal
# "$1" or "~$0.25" in SKILL.md is therefore silently rewritten to the invocation
# arguments (for example `awk '{print $1}'` became `awk '{print 143}'` for
# `--pr 143`). SKILL.md must contain no dollar-digit token at all.

bats_require_minimum_version 1.5.0

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq not available"
  load test_helper
  SKILL="${BATS_TEST_DIRNAME}/../skills/comprehensive-review/SKILL.md"
}

# Extract extract_findings() from SKILL.md by its column-0 closing brace and eval it.
# (load_function's brace counter mis-parses this function: a comment inside it
# contains a lone "}".)
load_extract_findings() {
  local body
  body=$(awk '/^extract_findings\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$SKILL")
  [ -n "$body" ] || { echo "extract_findings not found in SKILL.md"; return 1; }
  eval "$body"
}

@test "SKILL.md contains no dollar-digit token the harness would substitute" {
  run grep -nE '\$[0-9]' "$SKILL"
  # grep exits 1 when nothing matches. Print offenders on failure.
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
}

@test "SKILL.md still contains the intentional \$ARGUMENTS placeholder" {
  grep -qF '$ARGUMENTS' "$SKILL"
}

@test "extract_findings reads its agent name from its first argument" {
  load_extract_findings
  raw=$'prose\n```json-findings\n[{"severity":"High","finding":"x","file":"a.go","line":1}]\n```\n'
  run extract_findings "security-reviewer" "$raw"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.[0].source')" = "security-reviewer" ]
}

@test "extract_findings does not hardcode a source when called with different names" {
  load_extract_findings
  raw=$'```json-findings\n[{"severity":"Low","finding":"y","file":"b.go","line":2}]\n```\n'
  run extract_findings "blind-hunter" "$raw"
  [ "$(echo "$output" | jq -r '.[0].source')" = "blind-hunter" ]
}

@test "first-path-component pipeline counts distinct top-level entries" {
  cmd=$(grep -oE "cut -d/ -f1 \| sort -u \| wc -l" "$SKILL" | head -1)
  [ -n "$cmd" ]
  [ "$(printf '.claude-plugin/plugin.json\nCHANGELOG.md\nCHANGELOG.md\n' | cut -d/ -f1 | sort -u | wc -l | tr -d ' ')" = "2" ]
}

@test "symbol-frequency pipeline strips uniq -c counts and keeps order" {
  expr=$(grep -oE "sed -E 's/\^ \*\[0-9\]\+ \+//'" "$SKILL" | head -1)
  [ -n "$expr" ]
  run bash -c "printf 'foo\nbar\nfoo\nfoo\nbar\nbaz\n' | sort | uniq -c | sort -rn | sed -E 's/^ *[0-9]+ +//'"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "foo" ]
  [ "${lines[1]}" = "bar" ]
  [ "${lines[2]}" = "baz" ]
}
