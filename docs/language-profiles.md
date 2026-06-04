---
layout: default
title: Language Profiles
nav_order: 5
render_with_liquid: false
---

# Language Profiles

The skill ships per-language context profiles for 19 languages. When a language is detected in the diff, the corresponding profile is automatically injected into relevant agents' task descriptions.

## Supported languages

| Profile file | Covers |
|---|---|
| `go.md` | Go |
| `python.md` | Python |
| `typescript.md` | TypeScript / JavaScript |
| `javascript.md` | JavaScript |
| `php.md` | PHP / Drupal |
| `ruby.md` | Ruby / Rails |
| `rust.md` | Rust |
| `java.md` | Java |
| `c++.md` | C / C++ |
| `shell.md` | Shell / Bash |
| `csharp.md` | C# |
| `kotlin.md` | Kotlin |
| `swift.md` | Swift |
| `scala.md` | Scala |
| `lua.md` | Lua |
| `perl.md` | Perl |
| `sql.md` | SQL |
| `terraform.md` | Terraform |
| `yaml.md` | YAML |

## What profiles contain

Each profile provides language-specific context that agents would otherwise need to discover or infer:

- **Do-NOT-Flag idioms** — language patterns that look like bugs but are idiomatic (e.g., Go's blank identifier, Python's `pass`, shell errexit quirks)
- **Common bugs** — patterns the agent should actively look for
- **Language-specific security guidance** — e.g., SQL injection vectors specific to each language, PHP deserialization risks, Go `unsafe` usage
- **Idiomatic trust boundaries** — what counts as safe vs. untrusted input in this ecosystem
- **Framework conventions** — e.g., Drupal's hook system, Ruby on Rails conventions, Spring Boot patterns

## Profile injection

Profiles are injected at the agent task level — not hardcoded into agent prompts. This means:
- A Go repo gets Go context; a PHP repo gets PHP context
- Multi-language PRs get all relevant profiles injected
- **blind-hunter does not receive language profiles** — its zero-context constraint is preserved

## Adding a new language profile

To add a language profile:

1. Create `skills/comprehensive-review/language-profiles/<lang>.md` following the structure of existing profiles
2. The filename (lowercased, without extension) must match the extension-based language detection in `SKILL.md` Phase 0
3. Do not put language guidance in agent prompts directly — use language profiles so all agents benefit

Language detection is extension-based. For example, `.go` → `go`, `.php`/`.module`/`.theme`/`.inc`/`.install` → `php`, `.ts`/`.tsx` → `typescript`.
