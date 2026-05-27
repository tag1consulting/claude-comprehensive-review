## C#-Specific Review Context

When reviewing C# code, pay particular attention to:

### C# Validation Idioms (Do NOT Flag)
- `?.` (null-conditional) and `??` / `??=` (null-coalescing) — idiomatic null-safe access; not missing null checks
- `using` declarations and `using` statements for `IDisposable` — correct resource management; do not flag
- `is` pattern matching with deconstruction — idiomatic type narrowing; do not prefer `as` + null check
- `record` types with `with` expressions — immutable value objects; this IS safe immutability
- `ArgumentNullException.ThrowIfNull()` (.NET 6+) — idiomatic guard clause; do not prefer manual null check

### Common C# Bugs
- `async void` methods outside of event handlers — exceptions escape unobserved and crash the process; use `async Task` instead
- Not awaiting a `Task` — fire-and-forget drops exceptions; always `await`, `return`, or explicitly `_ = task` with a comment
- `ConfigureAwait(false)` missing in library code — can deadlock in synchronisation-context-heavy callers (ASP.NET, WinForms, WPF)
- `IEnumerable<T>` re-enumeration — LINQ queries are lazy and re-executed on each enumeration; materialise with `.ToList()` / `.ToArray()` when reused
- `IEnumerable<T>` vs `IQueryable<T>`: using `IEnumerable` methods on `IQueryable` pulls the full dataset into memory before filtering
- Mutable `struct` — value-type mutation through a copy is silently lost; flag mutable structs that are assigned and mutated separately
- Finaliser / Dispose pattern inconsistency — implementing a finaliser without `GC.SuppressFinalize(this)` in `Dispose()` causes double-cleanup

### Security (C#-specific)
- SQL via string interpolation or concatenation — SQL injection; use parameterised queries or an ORM
- `XmlDocument` / `XmlReader` with external entity resolution enabled — XXE; set `XmlResolver = null` or use `XmlReader.Create` with safe settings
- `BinaryFormatter` / `SoapFormatter` / `NetDataContractSerializer` — unsafe deserialisation, arbitrary code execution; use `System.Text.Json` or `Newtonsoft.Json` with type handling disabled
- Nullable reference types disabled (`#nullable disable`) in new code — loses compiler-enforced null safety; require justification
- Secrets in `appsettings.json` checked into source control — use `dotnet user-secrets`, environment variables, or Azure Key Vault

### Nullable Reference Types
- Enabling `<Nullable>enable</Nullable>` project-wide is preferred; do not suppress warnings with `!` without a comment explaining why the value is known non-null
