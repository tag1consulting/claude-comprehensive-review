# Core — claude-comprehensive-review

Claude Code plugin distributing the `/comprehensive-review` skill and 7 custom agents. Pure markdown — no build system, no compiled artifacts. Distributed via the `tag1consulting` plugin marketplace.

## Source map

```
.claude-plugin/plugin.json          plugin manifest (name, version, author)
skills/comprehensive-review/
  SKILL.md                          orchestrator: Phases 0–5, all workflow logic
  GOVERNANCE.md                     shared directives inlined into every agent's task
  HELP.md                           user-facing flag reference
  SEVERITY.md                       severity normalization + confidence scale
  suppressions.json                 global suppression rules
  language-profiles/                per-language review context (*.md, one per lang)
  scripts/
    run-cve-check.sh                OSV.dev CVE check (Phase 1b)
    run-shellcheck.sh / run-semgrep.sh / run-trufflehog.sh / run-ruff.sh
    run-golangci-lint.sh / run-checkov.sh   optional static analyzers
agents/
  pr-summarizer.md                  Block A generation
  issue-linker.md                   issue cross-referencing (GitHub only)
  security-reviewer.md              OWASP-class security analysis (Opus)
  architecture-reviewer.md          design-pattern / coupling analysis (Opus)
  blind-hunter.md                   context-free "fresh eyes" review (Sonnet)
  edge-case-hunter.md               boundary-condition path tracing (Sonnet)
  adversarial-general.md            holistic completeness/operational review (Opus)
tests/
  *.bats                            bats test suite (54 tests, bash/jq required)
  fixtures/                         test input fixtures
examples/
  claude-security-guidance.example.md   copy-and-fill security policy template
.serena/                            Serena project config + memories
```

## Key invariants

- No build step — all deliverables are markdown files.
- External dependency: `pr-review-toolkit` agents (not in this repo).
- Optional dependency: `security-guidance` plugin (ambient hook-based security review).
- `SKILL.md` is the single source of truth for workflow logic and phase ordering.
- Agent files define scope boundaries; coordination lives entirely in `SKILL.md`.
- `README.md` and `CLAUDE.md` must stay in sync with `SKILL.md` flag tables and agent roster.

See `mem:tech_stack`, `mem:conventions`, `mem:suggested_commands`, `mem:task_completion`.
