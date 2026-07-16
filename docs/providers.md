---
layout: default
title: Provider Support
nav_order: 10
render_with_liquid: false
---

# Provider Support

The skill auto-detects your git hosting provider from the remote URL. Use `--provider <name>` to override for self-hosted instances with non-standard hostnames.

## Feature matrix

| Feature | GitHub / GHE | GitLab | Bitbucket |
|---------|:---:|:---:|:---:|
| Auto-detection | Yes | Yes | Yes |
| PR/MR creation (`--create-pr`) | Yes | Yes | Yes |
| Summary posting (`--post-summary`) | Yes | Yes | Yes |
| Inline review posting (`--post-findings`) | Yes | Yes | No ¹ |
| Draft/staged review (`--post-findings` default) | Yes ⁴ | Yes ⁴ | No ¹ ⁴ |
| `--read-back` (read your edited draft) | Yes | Yes | No ⁴ |
| External review (`--pr <N>`) | Yes | Yes | Yes |
| Inline review on external PR | Yes | Yes | No ¹ |
| Issue cross-referencing (issue-linker) | Yes | No ² | No ² |
| `REQUEST_CHANGES` review event | Yes | N/A ³ | N/A |

¹ Bitbucket does not support inline diff comments via API. Findings are posted as a single PR comment.  
² Issue cross-referencing is currently GitHub-only. The issue-linker agent is gracefully skipped for other providers.  
³ GitLab has no single-call "submit review" API. Inline comments are posted as individual discussion threads.  
⁴ `--post-findings` stages an editable draft by default (GitHub: pending review; GitLab: draft notes) — visible only to you until you submit it yourself; add `--publish` for the old immediate-post behavior. Bitbucket has no verified draft-create path in the public REST API, so `--post-findings` there always publishes, regardless of `--draft`/`--publish`, and `--read-back` is unavailable. `--read-back` works on both GitHub and GitLab for reporting what you kept/edited/removed, but staging newly-noticed findings into the existing draft only works on GitLab (draft notes can be appended one at a time) — on GitHub, the REST API can't append to an existing pending review, so new findings are reported in the terminal for you to add yourself.

## GitHub / GitHub Enterprise

**CLI required:** [gh CLI](https://cli.github.com/)

For GitHub Enterprise with a non-standard hostname, use:

```
/comprehensive-review --provider github
```

## GitLab

**CLI required:** [glab CLI](https://gitlab.com/gitlab-org/cli)

GitLab uses "Merge Request" (MR) terminology. All user-facing output uses "MR" when on GitLab. GitLab inline comments are posted as individual discussion threads rather than a single review event (GitLab's API does not have a review-submission model).

## Bitbucket

**Environment variables required:**

| Variable | Description |
|----------|-------------|
| `BITBUCKET_EMAIL` | Your Atlassian account email address |
| `BITBUCKET_TOKEN` | Atlassian API token from `id.atlassian.com` (`BITBUCKET_APP_PASSWORD` is auto-mapped if set) |

Bitbucket does not support inline diff comments via the REST API, and there is no verified draft-create path in the public API (the Cloud "Batched comments" staging feature is documented as UI-driven, not API-driven). When `--post-findings` is used, all findings are always posted as a single, immediately published PR comment — `--draft`/`--publish` have no effect on Bitbucket, and `--read-back` is unavailable.

## Manual provider override

```
/comprehensive-review --provider github
/comprehensive-review --provider gitlab
/comprehensive-review --provider bitbucket
```

Use this when the auto-detection fails for self-hosted instances with non-standard domain names.
