## Ruby-Specific Review Context

When reviewing Ruby code, pay particular attention to:

### Common Bugs
- Missing `nil` guards — Ruby methods return `nil` on miss; chain `.nil?` or use `&.` safe navigation
- Mutation of shared state through `!` methods (`sort!`, `map!`, `gsub!`) on objects passed by reference
- `rescue Exception` catches `SignalException` and `SystemExit` — use `rescue StandardError` or a specific class
- `attr_accessor` exposing internals that should be read-only — prefer `attr_reader`
- String vs Symbol confusion in hash keys — `hash[:key]` vs `hash["key"]` are different
- Shadowing outer variables in blocks — `do |x|` where `x` is already defined in the outer scope

### Security
- `eval` / `instance_eval` / `class_eval` with user input — arbitrary code execution
- `Marshal.load` on untrusted data — arbitrary object instantiation and code execution
- `send` / `public_send` with user-controlled method names — privilege escalation
- Regex with `.*` and unbounded repetition — ReDoS risk; prefer `\A`/`\z` anchors over `^`/`$`
- `open(user_input)` — can invoke a subprocess if input starts with `|`
- Mass assignment via `params.permit!` or missing Strong Parameters in Rails — attribute injection

### Idiomatic Ruby
- Prefer `map`/`select`/`reduce` over manual `each` accumulation
- Use `frozen_string_literal: true` magic comment to catch unintended mutation
- Prefer `Struct` or `Data` (Ruby 3.2+) for plain value objects over bare hashes
- Return values are implicit — avoid redundant `return` except for early exits
- `protected` is rarely needed; prefer `private` for internal methods

### Rails-Specific (if applicable)
- N+1 queries — use `includes`/`eager_load`/`preload`; flag `.each` loops that call associations
- `find_by` returns `nil` on miss; `find` raises `ActiveRecord::RecordNotFound` — use the right one
- Raw SQL interpolation in `where("col = #{val}")` — always use parameterized form `where("col = ?", val)`
- `before_action` callbacks that skip authentication for specific actions — verify the exclusion is intentional
- Storing sensitive data in session or cookies without encryption

### Do NOT flag
- Trailing commas in multiline hashes/arrays — idiomatic Ruby style
- `unless` / `until` — valid Ruby idioms, not anti-patterns
