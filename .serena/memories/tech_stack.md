# Tech Stack

## Language & runtime
- **Primary language**: Bash (shell scripts in `scripts/`; bats test suite)
- **Content format**: Markdown (all agents, skills, docs — the majority of the repo)
- **No compiled code, no build pipeline**

## Test framework
- `bats` (Bash Automated Testing System) — `tests/*.bats`
- Requires: `bats`, `jq`
- 54 tests across 4 test files

## Distribution
- Claude Code plugin marketplace (`tag1consulting` org)
- Plugin manifest: `.claude-plugin/plugin.json`
- Version format: semver without `v` prefix in `plugin.json`; git tags use `v` prefix (e.g., `v1.10.0`)

## External tools used at review runtime (all optional/opportunistic)
- `shellcheck`, `semgrep`, `trufflehog`, `ruff`, `golangci-lint`, `checkov` — skip silently if absent
- `jq` — required by CVE check script and bats tests
- `curl` — used by CVE check (OSV.dev API) and claude-mem integration

## Language servers (Serena)
- Configured for `bash` only (`project.yml`)
