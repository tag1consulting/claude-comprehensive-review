---
layout: default
title: Static Analyzers
nav_order: 4
render_with_liquid: false
---

# Static Analyzers

In addition to LLM agents, the skill runs deterministic checks when relevant files appear in the diff. All checks are **opportunistic** — if the binary is not installed, the check is silently skipped with no error.

## Analyzer table

| Check | Trigger | Runs in `--quick`? | Binary required |
|-------|---------|-------------------|----------------|
| **dependency-check** — queries [OSV.dev](https://osv.dev/) for known CVEs in declared dependency versions | `go.mod`, `package.json`, `requirements*.txt`, or `composer.json` changed | Yes | `curl` + `jq` (built-in) |
| **shellcheck** — shell script linting | `.sh` or `.bash` files changed | Yes | `shellcheck` |
| **semgrep** — polyglot SAST | Any source file changed | Yes | `semgrep` |
| **trufflehog** — secret scanning | Any file changed | Yes | `trufflehog` |
| **ruff** — Python linting | `.py` files changed | Yes | `ruff` |
| **golangci-lint** — Go static analysis | `.go` files changed | Yes | `golangci-lint` |
| **checkov** — IaC security scanning | `*.tf`, `*.tfvars`, `Dockerfile`, k8s YAML, CloudFormation, Azure ARM changed | Yes | `checkov` |
| **eslint** — JavaScript/TypeScript linting | `.js`, `.jsx`, `.ts`, `.tsx`, `.mjs`, `.cjs` files changed; only runs when an ESLint config is present | No | `eslint` (via `npx` or `node_modules/.bin`) |
| **hadolint** — Dockerfile linting | `Dockerfile`, `Dockerfile.*`, or `*.dockerfile` changed | No | `hadolint` |
| **kube-linter** — Kubernetes manifest linting | `.yaml`, `.yml`, or `.json` files containing `apiVersion` and `kind` fields | No | `kube-linter` |
| **phpcs** — PHP CodeSniffer | `.php` files changed; uses Drupal/DrupalPractice standard when available, falls back to PSR-12 | No | `phpcs` |
| **phpstan** — PHP static analysis | `.php`, `.module`, `.inc`, `.install`, `.theme` files changed | No | `phpstan` |
| **tflint** — Terraform linting | `.tf` or `.tfvars` files changed; runs per-directory | No | `tflint` |

Findings appear in Block B with the tool name as source (e.g., `[shellcheck]`, `[eslint]`).

## Installing analyzers

All analyzers are optional and opportunistic. Install only those relevant to your codebase:

```bash
# macOS via Homebrew
brew install shellcheck hadolint kube-linter tflint

# Python-based (pip)
pip install semgrep ruff checkov

# Go-based
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

# TruffleHog — see https://github.com/trufflesecurity/trufflehog/releases
# or: brew install trufflehog

# JavaScript
npm install -g eslint

# PHP
composer global require squizlabs/php_codesniffer phpstan/phpstan
```

## CVE check details

The `dependency-check` script queries [OSV.dev](https://osv.dev/)'s batch API for known vulnerabilities in dependency versions declared in changed manifests. No API key required. Network failures are non-blocking.

Supported manifest files:
- `go.mod` — Go modules (handles `replace` directives)
- `package.json` — npm/Node.js
- `requirements*.txt` — Python pip
- `composer.json` — PHP Composer

CVE findings include severity (CVSS-mapped to Critical/High/Medium/Low), CVE ID, affected package and version, and a remediation note with the fixed version. Findings below CVSS threshold are emitted as `"High"` as a conservative fallback.

The `dependency-check` runs in both full and `--quick` mode when manifest files are present. It also runs in `--security-only` mode (CVE checks are security checks).

## Static analyzer scripts

Each analyzer has a dedicated script in `skills/comprehensive-review/scripts/`:

| Script | Analyzer |
|--------|---------|
| `run-cve-check.sh` | OSV.dev CVE batch lookup |
| `run-shellcheck.sh` | ShellCheck |
| `run-semgrep.sh` | Semgrep SAST |
| `run-trufflehog.sh` | TruffleHog secret scanning |
| `run-ruff.sh` | Ruff Python linting |
| `run-golangci-lint.sh` | golangci-lint |
| `run-checkov.sh` | Checkov IaC scanning |
| `run-eslint.sh` | ESLint |
| `run-hadolint.sh` | Hadolint |
| `run-kube-linter.sh` | kube-linter |
| `run-phpcs.sh` | PHP CodeSniffer |
| `run-phpstan.sh` | PHPStan |
| `run-tflint.sh` | tflint |

Each script reads changed file paths from stdin and emits a `json-findings` JSON array with a stamped `source` field, flowing into the same dedup/suppress/normalize pipeline as agent findings.
