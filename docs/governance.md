---
layout: default
title: Governance
nav_order: 8
render_with_liquid: false
---

# Governance

Every spawned agent receives a shared governance block (`skills/comprehensive-review/GOVERNANCE.md`) inlined into its task description. This ensures consistent behavior across all agents without duplicating rules in individual agent prompts.

## Shared agent directives

| Directive | What it means |
|-----------|--------------|
| **Harm prioritization** | Findings that risk user harm (data loss, security exposure, breaking shared systems) are top priority. Agents surface adjacent harms even if outside their strict scope. |
| **No self-preservation** | Agents do not suppress findings or hide uncertainty to make output look cleaner. Uncertain findings are marked as such. |
| **Verify before naming** | Before naming a file, function, flag, package, version, or any other identifier in a recommendation, agents verify it exists in the current repo state via Read or Grep. Training-data recall is not verification. |
| **Don't reinvent the wheel** | Agents flag reimplementations of stdlib, framework, or existing repo helpers, citing the existing thing by name after verifying. |
| **No defensive code for impossible cases** | Agents do not recommend validation/error handling for scenarios that cannot occur given system invariants. Only validate at system boundaries. |
| **Non-destructive remediations** | Agents do not recommend force-push, `git reset --hard`, `DROP TABLE`, `terraform destroy`, etc., as fixes without an explicit caveat and rollback note. |
| **Named rejected alternatives** | Non-trivial fix recommendations include at least one rejected alternative and the reason it was rejected. |
| **Surfaced counter-arguments** | High-impact recommendations state the strongest argument against the recommendation before stating the recommendation itself. |
| **Secret redaction at source** | Agents redact API keys, tokens, passwords, etc., in their finding text, replacing them with `<secret-redacted>`. |
| **Evidence citations** | Findings cite evidence inline — `file:line` plus the relevant snippet, symbol, or pattern. The `json-findings` location fields are not the citation. |

## blind-hunter exception

`blind-hunter` receives the GOVERNANCE block but with one override: "verify before naming" applies only within the diff or file list it was given — never the broader repo. This preserves blind-hunter's zero-context "fresh eyes" purpose while keeping every other directive in force.

## Orchestrator governance

The orchestrator itself follows a separate set of rules (in the "Orchestrator Governance" section of `SKILL.md`):

- **External posting is gated by explicit flags** — each posting flag is the user's authorization checkpoint. The orchestrator does not post without an explicit flag.
- **`--create-pr` is hard-refused from the default branch** — creating a PR from `main` or `master` is blocked regardless of flags.
- **User confirmation is required before any external write** — the orchestrator pauses and prompts before posting to GitHub, GitLab, or Bitbucket.

## Secret redaction defense-in-depth

Secret redaction happens at two layers:

1. **Agent source (GOVERNANCE.md directive)** — agents are instructed to redact secrets in their finding text before emitting findings
2. **Phase 2 redaction pass** — the orchestrator runs a hardcoded-pattern redaction pass against all collected findings before any external posting, as defense-in-depth against agent failures

Both layers are always active regardless of flags.

## Incoherent input handling

If an agent receives a diff that contradicts its own commit message, claims to fix code it does not touch, or partially reverts an earlier commit without explanation, it is instructed to surface that as a top-level finding rather than reviewing line-by-line as if the diff were coherent.
