#!/usr/bin/env bats
# Regression tests for Claude Code's positional-argument substitution.
#
# The harness replaces $0..$9 (0-indexed) anywhere in a SKILL.md body, including
# inside bash code fences, whenever that argument index was supplied. See
# https://code.claude.com/docs/en/skills.md ("Available string substitutions").
# A literal "$1" or "~$0.25" in SKILL.md is therefore silently rewritten to the
# invocation arguments. For `--pr 143`, `awk -F/ '{print $1}'` (the tiny-tier
# architecture check) became `awk -F/ '{print 143}'`, and `local agent_name="$1"`
# in extract_findings became `local agent_name="143"`. SKILL.md must contain no
# dollar-digit token at all.
#
# Tests 3-7 run against a copy of SKILL.md with that substitution simulated
# (every $N replaced by ARGN). On a clean SKILL.md the copy is identical, so they
# pass. On a SKILL.md that contains dollar-digit tokens the simulated text breaks,
# so they fail. Set SKILL_UNDER_TEST to point the suite at a different file.

bats_require_minimum_version 1.5.0

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq not available"
  SKILL="${SKILL_UNDER_TEST:-${BATS_TEST_DIRNAME}/../skills/comprehensive-review/SKILL.md}"
  SIM="${BATS_TEST_TMPDIR}/SKILL.simulated.md"
  sed -E 's/\$([0-9])/ARG\1/g' "$SKILL" > "$SIM"
}

# Extract extract_findings() from the simulated SKILL.md by its column-0 closing
# brace and eval it. (test_helper's load_function brace counter mis-parses this
# function: a comment inside it contains a lone "}".)
load_extract_findings() {
  local body
  body=$(awk '/^extract_findings\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$SIM")
  [ -n "$body" ] || { echo "extract_findings not found in SKILL.md"; return 1; }
  eval "$body"
}

@test "SKILL.md contains no dollar-digit token the harness would substitute" {
  run grep -nE '\$[0-9]' "$SKILL"
  # grep exits 1 when nothing matches. Print offenders on failure.
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
}

@test "SKILL.md keeps the intentional \$ARGUMENTS placeholder and no other substitution form" {
  grep -qF '$ARGUMENTS' "$SKILL"
  # $ARGUMENTS[N] and ${N} are also substituted; named $name forms need an
  # `arguments:` frontmatter key, which must not be added.
  run grep -nE '\$ARGUMENTS\[|\$\{[0-9]' "$SKILL"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  run awk '/^---$/{n++; next} n==1 && /^arguments:/{print NR": "$0}' "$SKILL"
  [ -z "$output" ] || { echo "frontmatter declares named arguments: $output"; return 1; }
}

@test "extract_findings reads its agent name from its first argument" {
  load_extract_findings
  raw=$'prose\n```json-findings\n[{"severity":"High","finding":"x","file":"a.go","line":1}]\n```\n'
  run extract_findings "security-reviewer" "$raw"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.[0].source')" = "security-reviewer" ]
}

@test "extract_findings reads its second argument as the raw output and keeps the agent name" {
  load_extract_findings
  raw=$'```json-findings\n[{"severity":"Low","finding":"y","file":"b.go","line":2},{"severity":"Low","finding":"z","file":"c.go","line":3}]\n```\n'
  run extract_findings "blind-hunter" "$raw"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = "2" ]
  [ "$(echo "$output" | jq -r '[.[].source] | unique | .[0]')" = "blind-hunter" ]
}

@test "tiny-tier cross-directory check counts distinct top-level entries" {
  cmd=$(grep -F 'elif [[ $(echo "$TINY_DIFF_NAMES" |' "$SIM" \
    | sed -E 's/.*\$\((echo "\$TINY_DIFF_NAMES" \|[^)]*)\).*/\1/')
  [ -n "$cmd" ]
  TINY_DIFF_NAMES=$'.claude-plugin/plugin.json\nCHANGELOG.md\nCHANGELOG.md'
  run eval "$cmd"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
  TINY_DIFF_NAMES=$'docs/a.md\ndocs/b.md'
  run eval "$cmd"
  [ "$output" = "1" ]
}

@test "symbol-frequency pipeline strips uniq -c counts and keeps frequency order" {
  block=$(grep -F 'uniq -c | sort -rn' -A1 "$SIM" | sed -E 's# > /tmp/cr-symbols-freq-\$\$\.txt$##')
  [ -n "$block" ]
  DIFF_FILE="${BATS_TEST_TMPDIR}/diff.txt"
  printf 'foo baz foo bar\nfoo bar\n' > "$DIFF_FILE"
  export DIFF_FILE
  run eval "$block"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "foo" ]
  [ "${lines[1]}" = "bar" ]
  [ "${lines[2]}" = "baz" ]
}
