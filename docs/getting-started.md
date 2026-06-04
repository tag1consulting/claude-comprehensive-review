---
layout: default
title: Getting Started
nav_order: 1
render_with_liquid: false
---

# Getting Started

## Installation

### Option 1: Plugin install (recommended)

First, add the Tag1 Consulting marketplace (one-time setup, run in your terminal):

```bash
claude plugin marketplace add tag1consulting/claude-plugins
```

Then inside Claude Code, install the plugin and its required dependency:

```
/plugins install comprehensive-review@tag1consulting
/plugins install pr-review-toolkit@claude-plugins-official
```

Optionally, install the security-guidance companion plugin for ambient hook-based security review:

```
/plugins install security-guidance@claude-plugins-official
```

### Option 2: Manual installation

> **Note:** Agents must be installed under the `comprehensive-review:` plugin namespace. For manual installs, lay down the full plugin tree shown below, then update `~/.claude/plugins/installed_plugins.json` to register it.

```bash
PLUGIN_DIR=~/.claude/plugins/cache/tag1consulting/comprehensive-review/<version>

mkdir -p "$PLUGIN_DIR/.claude-plugin"
cp .claude-plugin/plugin.json "$PLUGIN_DIR/.claude-plugin/"

mkdir -p "$PLUGIN_DIR/skills/comprehensive-review"
cp skills/comprehensive-review/SKILL.md "$PLUGIN_DIR/skills/comprehensive-review/"
cp skills/comprehensive-review/HELP.md "$PLUGIN_DIR/skills/comprehensive-review/"
cp skills/comprehensive-review/SEVERITY.md "$PLUGIN_DIR/skills/comprehensive-review/"
cp skills/comprehensive-review/suppressions.json "$PLUGIN_DIR/skills/comprehensive-review/"
cp -r skills/comprehensive-review/language-profiles "$PLUGIN_DIR/skills/comprehensive-review/"

mkdir -p "$PLUGIN_DIR/agents"
cp agents/pr-summarizer.md "$PLUGIN_DIR/agents/"
cp agents/issue-linker.md "$PLUGIN_DIR/agents/"
cp agents/security-reviewer.md "$PLUGIN_DIR/agents/"
cp agents/architecture-reviewer.md "$PLUGIN_DIR/agents/"
cp agents/blind-hunter.md "$PLUGIN_DIR/agents/"
cp agents/edge-case-hunter.md "$PLUGIN_DIR/agents/"
cp agents/adversarial-general.md "$PLUGIN_DIR/agents/"

mkdir -p "$PLUGIN_DIR/skills/comprehensive-review/scripts"
for s in skills/comprehensive-review/scripts/*.sh; do
  cp "$s" "$PLUGIN_DIR/skills/comprehensive-review/scripts/"
  chmod +x "$PLUGIN_DIR/skills/comprehensive-review/scripts/$(basename "$s")"
done
```

Then register the plugin in `~/.claude/plugins/installed_plugins.json` and install the dependency:

```
/plugins install pr-review-toolkit@claude-plugins-official
```

## Requirements

| Requirement | Notes |
|-------------|-------|
| [Claude Code](https://claude.ai/code) | CLI or desktop app |
| `git` | Required for diff analysis |
| [gh CLI](https://cli.github.com/) | Required for GitHub / GitHub Enterprise |
| [glab CLI](https://gitlab.com/gitlab-org/cli) | Required for GitLab |
| `BITBUCKET_EMAIL` env var | Required for Bitbucket — your Atlassian account email address |
| `BITBUCKET_TOKEN` env var | Required for Bitbucket — Atlassian API token from `id.atlassian.com` |
| `jq` | Required for GitLab and Bitbucket (JSON parsing) |
| `pr-review-toolkit@claude-plugins-official` | Required — provides code-reviewer, silent-failure-hunter, pr-test-analyzer, comment-analyzer, type-design-analyzer |
| `security-guidance@claude-plugins-official` | Recommended — ambient hook-based security review; also wires up the shared org security policy |

## Running your first review

Run from any git repository on the branch you want to review:

```
/comprehensive-review
```

By default, everything runs locally — no PR is created, no remote posting occurs. This is intentional: posting to your hosting provider requires explicit opt-in flags.

**Model tip:** Run this skill on **Sonnet** (not Opus). The orchestrator does structured workflow coordination, not deep reasoning. Opus is reserved for the internally-spawned `architecture-reviewer` and `security-reviewer` agents. Running on Opus costs ~$60–80 for a medium PR; Sonnet costs ~$30–45.

## Updating

```
/plugins update comprehensive-review@tag1consulting
```

## Uninstalling

```
/plugins uninstall comprehensive-review@tag1consulting
```

For manual installs, remove `~/.claude/plugins/cache/tag1consulting/comprehensive-review`, then remove the `comprehensive-review@tag1consulting` entry from `~/.claude/plugins/installed_plugins.json` and `enabledPlugins` in `~/.claude/settings.json`.

## Org security policy

Both `comprehensive-review` and the `security-guidance` plugin read the same
`claude-security-guidance.md` policy file. Drop one in any of these locations to have
both tools apply the same codebase-specific security rules automatically:

| Path | Scope |
|------|-------|
| `~/.claude/claude-security-guidance.md` | User-wide (all repos) |
| `<repo>/.claude/claude-security-guidance.md` | Project-wide (commit this) |
| `<repo>/.claude/claude-security-guidance.local.md` | Local overrides (gitignore this) |

All three are loaded and concatenated (user → project → project-local) into the security-reviewer's task description. The combined budget is capped at 8 KB — if files exceed this, the tail is truncated first, preserving user-wide rules.

Example:

```markdown
# Org security rules

- All SELECTs against the `customers` or `orders` tables MUST go through `db.replica`.
- Background jobs must not use the user-context auth token; use service-account creds.
- Calls to `requests.get(url)` with user-controlled input need the SSRF-allowlist wrapper.
```

For a fuller annotated starting point, copy [`examples/claude-security-guidance.example.md`](https://github.com/tag1consulting/claude-comprehensive-review/blob/main/examples/claude-security-guidance.example.md) into your repo's `.claude/` directory and rename it to `claude-security-guidance.md`.
