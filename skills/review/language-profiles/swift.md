## Swift-Specific Review Context

When reviewing Swift code, pay particular attention to:

### Swift Validation Idioms (Do NOT Flag)
- `guard let x = x else { return }` — idiomatic early exit; do not prefer force-unwrap
- `if let` / `guard let` chains — safe optional binding; not excessive defensive coding
- `defer { }` for cleanup — guaranteed execution before scope exit; this IS resource management
- `Result<T, Error>` return type — explicit error propagation; do not prefer throwing functions without context
- `@discardableResult` — intentional; do not flag unused return values on annotated functions

### Common Swift Bugs
- Force-unwrap `!` on optionals that can realistically be `nil` at runtime — `fatal error: unexpectedly found nil`; prefer `guard let`, `if let`, or `??`
- Implicitly unwrapped optionals (`var x: String!`) outside of `@IBOutlet`/`@IBAction` — hidden nil crash risk
- Capture list omission in closures referencing `self` — strong reference cycle if `self` holds the closure; use `[weak self]` or `[unowned self]`
- `unowned` capture when the referenced object may be deallocated before the closure executes — use `weak` instead
- Mutating a `struct` inside a closure that captures it by value — mutations are invisible to the caller
- `Task { }` without cancellation handling — long-running tasks not tied to a structured scope may outlive their owners

### Security (Swift-specific)
- `Codable` decoding without specifying `keyDecodingStrategy` — unexpected keys are silently ignored; use strict decoding for security-sensitive payloads
- `URLSession` with `NSURLAuthenticationMethodServerTrust` and no certificate validation — disables TLS verification
- Storing secrets in `UserDefaults` or plist files — accessible to backup tools and other apps on non-jailbroken devices; use the Keychain
- `@MainActor` boundary violations — background code calling UI APIs without dispatching to main actor causes crashes

### Concurrency (Swift Concurrency / async-await)
- Calling `await` inside a `@MainActor` context for long-running I/O — blocks UI rendering; perform I/O off the main actor
- `actor` isolation violations — accessing actor-isolated state from a non-isolated context without `await` is a compile error; do not suppress warnings
- `Task.detached` without a structured scope — use `async let` or `withTaskGroup` for child tasks with bounded lifetimes
