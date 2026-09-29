#!/usr/bin/env bash
# check-model-pricing.sh — detect drift between Anthropic's published model
# pricing table and the committed snapshot in
# skills/comprehensive-review/model-pricing.json.
#
# The snapshot's `blended_rates` feed the Phase 5 cost estimate in SKILL.md.
# This script only compares the published per-model list prices (`.models`),
# because the blended rates are calibrated by hand from measured transcripts.
#
# Usage:
#   scripts/check-model-pricing.sh            # compare, print Markdown report
#   scripts/check-model-pricing.sh --update   # rewrite .models in the snapshot
#
# Exit codes:
#   0  no drift
#   1  drift detected (Markdown report on stdout)
#   2  fetch or parse failure (message on stderr, never reported as "no drift")
#
# Environment:
#   PRICING_URL        override the source page
#   PRICING_SNAPSHOT   override the snapshot path
#   PRICING_MOCK_FILE  read this file instead of fetching (offline testing only,
#                      never set in production)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRICING_URL="${PRICING_URL:-https://platform.claude.com/docs/en/about-claude/pricing.md}"
SNAPSHOT="${PRICING_SNAPSHOT:-${REPO_ROOT}/skills/comprehensive-review/model-pricing.json}"
MIN_ROWS=5

fail() { echo "check-model-pricing: $*" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || fail "jq is required"

fetch_page() {
  if [ -n "${PRICING_MOCK_FILE:-}" ]; then
    cat "$PRICING_MOCK_FILE" || fail "cannot read PRICING_MOCK_FILE"
  else
    curl -fsSL --max-time 30 --retry 2 "$PRICING_URL" || fail "could not fetch $PRICING_URL"
  fi
}

# Emit TSV rows: model, input, cache_write_5m, cache_write_1h, cache_hit, output.
# Reads the first Markdown table whose header contains "Base input tokens".
parse_table() {
  awk -F'|' '
    function clean(s) {
      gsub(/<sup>[^<]*<\/sup>/, "", s)
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    function price(s,   m) {
      s = clean(s)
      if (match(s, /\$[0-9]+(\.[0-9]+)?/)) return substr(s, RSTART + 1, RLENGTH - 1)
      return "NaN"
    }
    function model(s) {
      s = clean(s)
      sub(/ \(.*$/, "", s)          # drop "(retired, ...)" and "(limited availability)" notes
      gsub(/\[|\]/, "", s)
      return s
    }
    !intable && /^\|/ && /Base input tokens/ { intable = 1; skip = 1; next }
    intable && skip { skip = 0; next }   # separator row
    intable && /^\|/ {
      printf "%s\t%s\t%s\t%s\t%s\t%s\n", model($2), price($3), price($4), price($5), price($6), price($7)
      next
    }
    intable { exit }
  '
}

# jq 1.7 parses "NaN" as a number (printed as null), so num() rejects NaN and infinities.
to_json() {
  jq -R -s '
    def num: (tonumber? // null) | if type == "number" and (isnan | not) and (isinfinite | not) then . else error("non-numeric price") end;
    split("\n") | map(select(length > 0) | split("\t")) |
    map({key: .[0], value: {
      input: (.[1] | num), cache_write_5m: (.[2] | num),
      cache_write_1h: (.[3] | num), cache_hit: (.[4] | num),
      output: (.[5] | num)}}) | from_entries'
}

PAGE=$(fetch_page)
ROWS=$(printf '%s\n' "$PAGE" | parse_table)
[ -n "$ROWS" ] || fail "no pricing table found (header 'Base input tokens' missing): page layout may have changed"

CURRENT=$(printf '%s\n' "$ROWS" | to_json) || fail "non-numeric price in parsed table: page layout may have changed"
COUNT=$(jq 'length' <<<"$CURRENT")
[ "$COUNT" -ge "$MIN_ROWS" ] || fail "parsed only $COUNT rows (expected >= $MIN_ROWS): page layout may have changed"

if [ "${1:-}" = "--update" ]; then
  [ -f "$SNAPSHOT" ] || fail "snapshot not found: $SNAPSHOT"
  tmp=$(mktemp)
  jq --argjson m "$CURRENT" '.models = $m' "$SNAPSHOT" > "$tmp" && mv "$tmp" "$SNAPSHOT"
  echo "Updated $SNAPSHOT ($COUNT models)"
  exit 0
fi

[ -f "$SNAPSHOT" ] || fail "snapshot not found: $SNAPSHOT"
SNAP=$(jq '.models' "$SNAPSHOT") || fail "snapshot is not valid JSON"

REPORT=$(jq -r -n --argjson old "$SNAP" --argjson new "$CURRENT" '
  def fmt: "$\(.input) in / $\(.output) out / $\(.cache_hit) cache hit";
  ([$new | keys[] | select(. as $k | $old | has($k) | not) | "- **Added:** \(.) (\($new[.] | fmt))"] +
   [$old | keys[] | select(. as $k | $new | has($k) | not) | "- **Removed:** \(.) (was \($old[.] | fmt))"] +
   [$new | keys[] | select(. as $k | ($old | has($k)) and ($old[$k] != $new[$k])) |
     "- **Changed:** \(.) (was \($old[.] | fmt), now \($new[.] | fmt))"]) | .[]')

if [ -z "$REPORT" ]; then
  echo "No pricing drift ($COUNT models match the snapshot)."
  exit 0
fi

printf '%s\n' "$REPORT"
exit 1
