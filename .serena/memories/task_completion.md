# Task Completion

When a coding task is done:

1. **Run tests**: `bats tests/*.bats` — must pass (requires `bats` + `jq`)
2. **Lint shell scripts** (if `scripts/` changed): `shellcheck skills/comprehensive-review/scripts/*.sh`
3. **Check docs sync**: if `SKILL.md` flags/agents changed, verify `README.md` and `HELP.md` are in sync
4. **Before any release PR**: run `/comprehensive-review` on the branch first (project policy)

No formatter, no type checker, no build step — the test suite + shellcheck are the full quality gate for code changes. Markdown-only changes have no automated quality gate.
