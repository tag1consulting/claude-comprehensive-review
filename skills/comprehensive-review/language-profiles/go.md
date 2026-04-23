## Go-Specific Review Context

When reviewing Go code, pay particular attention to:

### Error Handling
- Every error return must be checked — `if err != nil` is not optional
- Errors should be wrapped with context: `fmt.Errorf("operation failed: %w", err)`
- Never ignore errors from `Close()`, `Flush()`, or deferred cleanup functions
- Check for naked `return err` without wrapping (loses call context)

### Common Go Bugs
- Unchecked type assertions — use the two-value form: `val, ok := x.(Type)`
- Loop variable capture in goroutines — `go func(v T) { ... }(v)` not `go func() { use(v) }()`
- Nil pointer dereference — check pointer returns before use
- Slice/map nil vs empty confusion — `var s []T` is nil, `make([]T, 0)` is empty
- Goroutine leaks — ensure goroutines have exit conditions
- Race conditions — shared state accessed from goroutines without sync

### Security (Go-specific)
- `unsafe` package usage should be flagged
- `exec.Command` with user-controlled input — command injection risk
- `InsecureSkipVerify: true` in TLS config
- `net/http` default client has no timeout — always set timeouts

### Idiomatic Go
- Return early on error, don't nest the happy path
- Accept interfaces, return structs
- Use `context.Context` for cancellation in long-running operations
- Prefer `errors.Is`/`errors.As` over string matching

### Pulumi Provider Patterns (if applicable)
- Resources must implement proper CRUD lifecycle (Create, Read, Update, Delete)
- State must be consistent after Create — return all computed fields
- Delete should be idempotent (handle "already deleted" gracefully)
- Diff/Check should not make API calls unless necessary
- Secrets should use `pulumi.ToSecret()` — never store secrets as plain outputs
