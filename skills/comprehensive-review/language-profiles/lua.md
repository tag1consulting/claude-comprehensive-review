## Lua-Specific Review Context

When reviewing Lua code, pay particular attention to:

### Lua Validation Idioms (Do NOT Flag)
- `x = x or default` — idiomatic default-value assignment; not missing nil check (but see truthiness note below)
- `local ok, err = pcall(fn, ...)` — idiomatic protected call for exception handling; this IS error handling
- `t[#t + 1] = value` — idiomatic table-as-array append; equivalent to `table.insert(t, value)`
- `module = module or {}` at the top of a file — idiomatic module initialization pattern

### Common Lua Bugs
- 1-based indexing: Lua arrays start at index `1`, not `0` — off-by-one errors when porting from other languages or using `#t` with mixed integer keys
- `nil` vs `false` in truthiness: `x = x or default` overwrites `x` when `x` is `false` (not just `nil`); use explicit `if x == nil then x = default end` when `false` is a valid value
- `local` discipline: variables without `local` are implicitly global — accidental globals pollute the global namespace and cause hard-to-trace bugs across modules
- `#` operator on tables with holes (non-contiguous integer keys) — length is undefined; use a counter variable or ensure contiguous keys
- Modifying a table while iterating with `pairs()` / `ipairs()` — undefined behaviour; iterate a copy or collect keys first
- String indexing: Lua strings are 1-based and immutable; `string.sub(s, 1, 1)` not `s[0]`

### Security (Lua-specific)
- `load()` / `loadstring()` / `dofile()` on untrusted input — arbitrary code execution; sandbox user scripts with a restricted environment (`setfenv` in Lua 5.1, `_ENV` override in Lua 5.2+)
- `string.format("%s", user_input)` passed to an OS call — injection risk; validate and escape user input before use in OS-level operations
- `io.popen()` / `os.execute()` with unsanitised strings — command injection; prefer whitelisted argument forms

### Idiomatic Lua
- Metatables and `__index` for inheritance — valid; do not flag OOP patterns using metatables as non-idiomatic
- `require()` caches modules in `package.loaded` — repeated `require` of the same module is safe and cheap; do not flag it
- Prefer `string.format` over concatenation (`..`) in hot paths — concatenation creates intermediate strings
