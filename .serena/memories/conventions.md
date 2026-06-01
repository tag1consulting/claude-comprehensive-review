# Conventions

## Markdown / agent files
- Agent files define scope + output format; coordination is in `SKILL.md` only.
- Every custom agent must emit a trailing ` ```json-findings ` block with fields: `severity`, `confidence` (0–100), `file`, `line`, `finding`, `remediation`, `source`.
- `GOVERNANCE.md` is the single place for governance directives shared across all agents. Do not duplicate directives into individual agent prompts.
- `blind-hunter` receives ZERO project context — only the raw diff or plain file list. Enforce this invariant when editing `SKILL.md`.
- BMAD attribution (`blind-hunter`, `edge-case-hunter`, `adversarial-general`) must be preserved.

## SKILL.md structure
- Phases 0–5; flag parse block in Phase 0; mode table in Phase 1.
- When adding a flag: update Phase 0 parse block, Phase 1 mode table, `README.md` flags table, `HELP.md`.
- When adding an agent: update agent roster table in `README.md`, Phase 1 launch conditions, severity normalization table in `SKILL.md`.

## Language profiles
- One file per language: `skills/comprehensive-review/language-profiles/<lang>.md`
- Filename (lowercased) must match extension-based language detection in `SKILL.md` Phase 0.
- Do NOT put per-language guidance directly in agent prompts.

## Suppressions
- Global rules in `suppressions.json`; per-repo overrides in `.claude/comprehensive-review/suppressions.json` (merged via `jq -s 'add'`).
- Do not add project-specific rules to the global file.

## Secrets
- Replace all real secret values with `<secret-redacted>` before any external posting.
- Phase 2 step 2f runs a hardcoded-pattern redaction pass in `SKILL.md` as defense-in-depth.

## Git / branching
- Never commit to `main` directly.
- Feature/fix work goes on branches with worktrees created outside the repo path.
- Commit messages include `Co-Authored-By: Claude <noreply@anthropic.com>` for AI-assisted work.
- No "Generated with Claude Code" in PR descriptions, issues, or comments.
