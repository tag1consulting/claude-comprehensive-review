# Severity Normalization Table

Read by the orchestrator in Phase 2. Maps each agent's native scale to the
unified Critical/High/Medium/Low scale.

| Agent | Their Scale | Maps To |
|-------|-------------|---------|
| code-reviewer | confidence [91,100] / [80,90] / [60,79] / [0,59] | Critical / High / Medium / Low |
| silent-failure-hunter | CRITICAL/HIGH/MEDIUM | pass through |
| comment-analyzer | Critical/High/Medium/Low | pass through |
| pr-test-analyzer | gap [8,10] / [5,7] / [3,4] / [1,2] | Critical / High / Medium / Low |
| type-design-analyzer | rating [1,2] / [3,5] / [6,10] | High / Medium / Low |
| architecture-reviewer, security-reviewer, adversarial-general | Critical/High/Medium/Low via json-findings | pass through |
| blind-hunter, edge-case-hunter | Critical/High/Medium/Low via json-findings | pass through |
| dependency-check (parsed CVSS) | Critical/High/Medium/Low | pass through (identity mapping) |
| dependency-check (CVSS unparsed / v4 / v2) | High | maps to High (conservative) |
| shellcheck | error/warning/info | High / Medium / Low |
| semgrep | ERROR/WARNING/INFO (or rule confidence) | Critical / High / Medium |
| trufflehog | verified/unverified | Critical / High |
| ruff | all findings | Medium |
| golangci-lint | all findings | Medium |

## Confidence Scale (0–100)

Custom agents (architecture-reviewer, security-reviewer, blind-hunter, edge-case-hunter,
adversarial-general) emit a `confidence` integer per finding in their `json-findings` block.

| Range | Label | Meaning |
|-------|-------|---------|
| 91–100 | Certain | Reproducible problem; no context needed |
| 76–90 | High | Strong evidence; minor ambiguity about runtime context |
| 51–75 | Moderate | Plausible but depends on context outside the diff |
| 26–50 | Low | Speculative; likely requires deeper context |
| 0–25 | Very low | Hunch or pattern-match; likely noise |

The `--min-confidence` flag (default: 75) filters out findings below the threshold
**before** suppression rules are applied. This ordering is load-bearing: confidence
filtering first ensures that verify-gated suppression rules don't burn registry HTTP
calls on sub-threshold noise.

### External agent confidence mapping

External pr-review-toolkit agents don't emit a confidence integer. For uniform
`--min-confidence` filtering, their numeric scores are mapped as follows:
- `pr-test-analyzer` gap score [1,10]: `confidence = gap_score * 10`
  (gap=8 → confidence=80; gap=3 → confidence=30)
- `type-design-analyzer` rating [1,10]: `confidence = (11 - rating) * 10`
  (low rating=2, meaning high concern → confidence=90; high rating=9, meaning low concern → confidence=20)
- `code-reviewer` already emits confidence [0,100]; no mapping needed.
- All other external agents (silent-failure-hunter, comment-analyzer): treat as confidence=80
  (above default threshold; filter does not apply unless `--min-confidence` > 80).
