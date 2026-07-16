---
layout: home
title: Home
nav_exclude: true
permalink: /
render_with_liquid: false
hero_title: Comprehensive Review
hero_tagline: "Comprehensive PR/MR review using parallel specialized agents. Produces structured summaries and severity-ranked findings from 10+ agents — right inside Claude Code."
---

<div class="features">
  <div class="feature">
    <h3><span class="feature-icon">&#9670;</span> 10+ Specialized Agents</h3>
    <p>Parallel fleet of agents: OWASP security, architecture coupling, blind "fresh eyes" review, edge-case path tracing, and more — all coordinated by a single skill.</p>
  </div>
  <div class="feature">
    <h3><span class="feature-icon">&#9670;</span> 13 Static Analyzers</h3>
    <p>Shellcheck, semgrep, trufflehog, ruff, golangci-lint, checkov, eslint, hadolint, kube-linter, phpcs, phpstan, tflint, and CVE checking via OSV.dev — all opportunistic.</p>
  </div>
  <div class="feature">
    <h3><span class="feature-icon">&#9670;</span> GitHub, GitLab, Bitbucket</h3>
    <p>Auto-detects your git provider. Creates PRs, posts inline reviews, and supports external PR review by number. Works with GitHub Enterprise.</p>
  </div>
  <div class="feature">
    <h3><span class="feature-icon">&#9670;</span> Token-Efficient by Design</h3>
    <p>Tiered context passing, per-agent scope boundaries, auto-cheap routing for docs/config diffs, and <code>--quick</code> mode for 60–80% cost reduction.</p>
  </div>
</div>

## What it does

When you run `/comprehensive-review` on a branch, it launches a parallel fleet of specialized agents, normalizes and deduplicates their findings into a unified severity ranking, then assembles two output blocks: a PR summary (Block A) and a findings report (Block B). Both blocks are always shown locally; remote posting to GitHub, GitLab, or Bitbucket requires explicit opt-in flags.

## Quick start

Install the plugin and its dependency inside Claude Code:

```
/plugins install comprehensive-review@tag1consulting
/plugins install pr-review-toolkit@claude-plugins-official
```

Then run on any branch:

```
/comprehensive-review
```

That's it — a full review runs locally with no PR created. Add `--create-pr` to open a PR with the summary as its description, or `--post-findings` to stage inline findings on an existing PR as an editable draft (GitHub pending review / GitLab draft notes) — nothing is published until you submit it yourself; add `--publish` to post immediately instead.

## Learn more

**Start here**

- [Getting started](getting-started) — Installation, requirements, provider setup
- [Usage & flags](usage) — All flags, examples, posting behavior

**Agents & analysis**

- [Agents](agents) — Full agent roster, models, when each runs, scope boundaries
- [Static analyzers](static-analyzers) — All 13 deterministic checks, CVE lookups, installation
- [Language profiles](language-profiles) — Per-language context for 19 languages

**Advanced topics**

- [Token efficiency](token-efficiency) — Tiered context passing, auto-cheap routing, cost expectations
- [Suppressions](suppressions) — Suppress false positives with JSON rules and verify-before-suppress
- [Governance](governance) — Shared agent directives, orchestrator rules, secret redaction
- [claude-mem integration](claude-mem) — Optional persistent cross-session review memory

**Reference**

- [Architecture](architecture) — File layout, phase overview, two-block output design
- [Provider support](providers) — GitHub, GitLab, Bitbucket feature matrix
