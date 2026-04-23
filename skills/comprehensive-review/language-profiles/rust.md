## Rust-Specific Review Context

When reviewing Rust code, pay particular attention to:

### Common Bugs
- `unwrap()` / `expect()` on `Option` or `Result` in production paths — panics on `None`/`Err`; use `?`, `if let`, or `match` instead
- Integer overflow in debug builds panics; in release builds it wraps — use `checked_*`, `saturating_*`, or `wrapping_*` arithmetic when overflow is possible
- Off-by-one in slice indexing — `&slice[0..n]` vs `&slice[0..=n]`
- `clone()` called inside a hot loop — often indicates a design issue; prefer borrowing
- Holding a `MutexGuard` across an `.await` point — deadlock risk in async code
- `mem::forget` or `ManuallyDrop` preventing `Drop` from running — resource leaks

### Security
- `unsafe` blocks — every use requires justification; flag any `unsafe` without a comment explaining the invariants upheld
- FFI boundary crossings — null pointer checks, buffer length validation, lifetime guarantees for pointers passed to C
- `std::str::from_utf8_unchecked` — only safe when caller guarantees valid UTF-8; flag without proof
- Secrets in `Debug` output — types holding credentials should implement `Debug` with redaction or use `secrecy` crate
- Dependency `unsafe` features enabled via `Cargo.toml` feature flags — flag unexpected `unsafe` feature enablement

### Idiomatic Rust
- Propagate errors with `?` rather than `unwrap` or manual `match` in functions that return `Result`
- Prefer `impl Trait` parameters over generics when the concrete type doesn't matter at call sites
- Use `#[derive(Debug, Clone, PartialEq)]` rather than manual implementations unless custom behavior is needed
- Prefer `Vec::with_capacity` when final size is known to avoid reallocations
- `Arc<Mutex<T>>` for shared mutable state across threads; `Rc<RefCell<T>>` for single-threaded interior mutability
- Lifetime elision is preferred; explicit lifetimes only when needed for clarity

### Do NOT flag
- `clone()` on types that are `Copy` — compiler optimizes these away
- `#[allow(dead_code)]` in library crates — items may be part of the public API
- Use of `todo!()` / `unimplemented!()` in scaffolding — only flag in non-test production paths
