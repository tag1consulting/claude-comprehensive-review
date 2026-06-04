---
layout: default
title: Suppressions
nav_order: 7
render_with_liquid: false
---

# Suppressions

The skill ships a default suppressions file and supports per-repo overrides. Suppressions prevent known false positives from appearing in every review.

## Suppression files

| Path | Scope |
|------|-------|
| `skills/comprehensive-review/suppressions.json` (in plugin) | Global defaults — shipped with the plugin |
| `<repo>/.claude/comprehensive-review/suppressions.json` | Per-repo overrides — merged with the global file |

Per-repo rules are merged with the global rules using `jq -s 'add'`. Rules in either file are evaluated together.

## Rule format

Each suppression rule has:

```json
{
  "id": "unique-identifier",
  "reason": "Human-readable explanation of why this is suppressed",
  "match": {
    "file": "optional/path/pattern",
    "pattern": "regex applied to finding text"
  },
  "verify": "optional-ecosystem"
}
```

- `id` — unique identifier for the rule
- `reason` — human-readable explanation (shown in Phase 5 output when a finding is suppressed)
- `match.pattern` — regex applied to finding text
- `match.file` — optional path pattern (both `file` and `pattern` must match when both are present)
- `verify` — optional ecosystem to call before suppressing (see below)

## Verify-before-suppress

Rules with a `verify` field call an external registry API to confirm the flagged version actually exists before suppressing. This prevents false suppressions when the version in the finding text is hallucinated.

| `verify` value | Registry called |
|---------------|----------------|
| `github-release` | GitHub Releases API |
| `npm` | registry.npmjs.org |
| `pypi` | pypi.org |
| `go-module` | proxy.golang.org |
| `cargo` | crates.io |
| `docker-hub` | hub.docker.com |
| `ruby-org` | cache.ruby-lang.org |

If the registry returns 2xx, the finding is suppressed. If it returns 404 or errors, the finding is kept (fail-open). This prevents a real Critical CVE from being silently suppressed because the version string happened to match.

## Adding per-repo rules

Create `.claude/comprehensive-review/suppressions.json` in your repo:

```json
[
  {
    "id": "known-false-positive-xyz",
    "reason": "Our framework always uses this pattern and it is safe in this context",
    "match": {
      "pattern": "specific pattern from the finding text"
    }
  }
]
```

## Disabling suppressions

Use `--no-suppress` to disable all suppression rules for a run. Useful for:
- Audit runs where you want to see every finding
- Debugging whether a rule is incorrectly suppressing a real issue

```
/comprehensive-review --no-suppress
```

> Do not add rules specific to a single project into the global suppressions file shipped with the plugin. Only project-neutral rules (e.g., version verification rules for widely-used versions) belong in the global file.
{: .warning }
