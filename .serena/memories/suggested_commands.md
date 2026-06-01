# Suggested Commands

## Tests
```bash
bats tests/*.bats          # run full test suite (requires bats + jq)
bats tests/run_cve_check.bats   # run just CVE check tests
```

## Installation (end users and contributors)
```bash
# Install or reinstall from marketplace (after tagging a pre-release or merging to main)
/plugins install comprehensive-review@tag1consulting
```
No `install.sh` — removed; marketplace install is the only supported path.

## Linting scripts (manual, for changed files)
```bash
shellcheck skills/comprehensive-review/scripts/*.sh
```

## Release workflow
1. Update `version` in `.claude-plugin/plugin.json`
2. Update plugin entry version in `tag1consulting/claude-plugins` marketplace repo
3. Tag this repo `v<version>`
4. Always run `/comprehensive-review` before creating the release PR
