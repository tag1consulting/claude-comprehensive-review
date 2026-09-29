#!/usr/bin/env bats
# Tests for scripts/check-model-pricing.sh and the blended-rate consistency
# between SKILL.md, docs/token-efficiency.md, and model-pricing.json.
# Fully offline: uses PRICING_MOCK_FILE and a temporary snapshot.

bats_require_minimum_version 1.5.0

setup() {
  command -v jq >/dev/null 2>&1 || skip "jq not available"
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/check-model-pricing.sh"
  FIX="${BATS_TEST_DIRNAME}/fixtures/pricing"
  WORK=$(mktemp -d)
  export PRICING_SNAPSHOT="${WORK}/snapshot.json"
  cp "${REPO_ROOT}/skills/comprehensive-review/model-pricing.json" "$PRICING_SNAPSHOT"
  # Seed the temporary snapshot from the base fixture.
  PRICING_MOCK_FILE="${FIX}/base.md" "$SCRIPT" --update >/dev/null
}

teardown() {
  rm -rf "$WORK"
}

@test "no drift: identical page exits 0" {
  PRICING_MOCK_FILE="${FIX}/base.md" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == "No pricing drift (6 models"* ]]
}

@test "parser strips notes, links, and sup tags from names and prices" {
  run jq -e '.models["Claude Opus 4.1"] == {input: 15, cache_write_5m: 18.75, cache_write_1h: 30, cache_hit: 1.5, output: 75}' "$PRICING_SNAPSHOT"
  [ "$status" -eq 0 ]
  run jq -e '.models["Claude Sonnet 5.5"] == {input: 2, cache_write_5m: 2.5, cache_write_1h: 4, cache_hit: 0.2, output: 10}' "$PRICING_SNAPSHOT"
  [ "$status" -eq 0 ]
}

@test "the table after the pricing table is not parsed" {
  run jq -e '.models | has("ignored")' "$PRICING_SNAPSHOT"
  [ "$status" -eq 1 ]
}

@test "price change: exits 1 and reports Changed" {
  PRICING_MOCK_FILE="${FIX}/price-changed.md" run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"**Changed:** Claude Sonnet 5.5"* ]]
  [[ "$output" == *'now $2.50 in / $12 out'* ]]
}

@test "added model: exits 1 and reports Added" {
  PRICING_MOCK_FILE="${FIX}/model-added.md" run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"**Added:** Claude Opus 6"* ]]
}

@test "removed model: exits 1 and reports Removed" {
  PRICING_MOCK_FILE="${FIX}/model-removed.md" run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"**Removed:** Claude Haiku 3.5"* ]]
}

@test "missing table header: exits 2, never reports no drift" {
  PRICING_MOCK_FILE="${FIX}/no-header.md" run --separate-stderr "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"no pricing table found"* ]]
  [[ "$output" != *"No pricing drift"* ]]
}

@test "too few rows: exits 2" {
  PRICING_MOCK_FILE="${FIX}/too-few-rows.md" run --separate-stderr "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"parsed only"* ]]
}

@test "non-numeric price: exits 2" {
  PRICING_MOCK_FILE="${FIX}/bad-price.md" run --separate-stderr "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"non-numeric price"* ]]
}

@test "missing snapshot: exits 2" {
  rm -f "$PRICING_SNAPSHOT"
  PRICING_MOCK_FILE="${FIX}/base.md" run --separate-stderr "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"snapshot not found"* ]]
}

@test "--update preserves blended_rates" {
  PRICING_MOCK_FILE="${FIX}/model-added.md" "$SCRIPT" --update >/dev/null
  run jq -c '.blended_rates' "$PRICING_SNAPSHOT"
  [ "$output" = '{"opus":8,"sonnet":4,"haiku":2}' ]
}

# ---------------------------------------------------------------------------
# Blended rates must agree across the snapshot, SKILL.md, and the docs page.
# ---------------------------------------------------------------------------

@test "blended rates in SKILL.md match model-pricing.json" {
  local snap="${REPO_ROOT}/skills/comprehensive-review/model-pricing.json"
  local skill="${REPO_ROOT}/skills/comprehensive-review/SKILL.md"
  for fam in Opus Sonnet Haiku; do
    local want got
    want=$(jq -r ".blended_rates.$(echo "$fam" | tr 'A-Z' 'a-z')" "$snap")
    got=$(grep -oE "${fam} blended ~\\\$[0-9.]+/M" "$skill" | grep -oE '[0-9.]+' | head -1)
    [ "$got" = "$want" ]
  done
}

@test "blended rates in docs/token-efficiency.md match model-pricing.json" {
  local snap="${REPO_ROOT}/skills/comprehensive-review/model-pricing.json"
  local line
  line=$(grep -E 'Est\. Cost \| Estimated cost from a blended' "${REPO_ROOT}/docs/token-efficiency.md")
  [[ "$line" == *"Opus ~\$$(jq -r .blended_rates.opus "$snap")/M"* ]]
  [[ "$line" == *"Sonnet ~\$$(jq -r .blended_rates.sonnet "$snap")/M"* ]]
  [[ "$line" == *"Haiku ~\$$(jq -r .blended_rates.haiku "$snap")/M"* ]]
}
