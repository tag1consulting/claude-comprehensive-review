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
| architecture-reviewer, security-reviewer | Critical/High/Medium | pass through (Medium+ only) |
| blind-hunter, edge-case-hunter | Critical/High/Medium/Low | pass through |
| dependency-check (parsed CVSS) | Critical/High/Medium/Low | pass through (identity mapping) |
| dependency-check (CVSS unparsed / v4 / v2) | High | maps to High (conservative) |
