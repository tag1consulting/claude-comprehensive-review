## Kotlin-Specific Review Context

When reviewing Kotlin code, pay particular attention to:

### Kotlin Validation Idioms (Do NOT Flag)
- `?.let { }` / `?.also { }` — idiomatic null-safe scoping; do not flag in favour of null checks
- `?: return` / `?: throw` — early-exit on null is idiomatic; do not flag as missing error handling
- `data class` with `copy()` — immutable value objects updated via copy; this IS safe immutability
- `sealed class` / `sealed interface` for exhaustive `when` branches — idiomatic algebraic types
- `@JvmStatic` / `@JvmOverloads` in companion objects — intentional Java interop; do not flag

### Common Kotlin Bugs
- `!!` (non-null assertion) on values that can realistically be null at runtime — `NullPointerException` risk; prefer safe call or `?: error(...)`
- `lateinit var` without checking `::field.isInitialized` — `UninitializedPropertyAccessException` if accessed before assignment
- `lazy { }` delegate in a multithreaded context without `LazyThreadSafetyMode.SYNCHRONIZED` — race condition
- Coroutine exception swallowed silently — `launch {}` exceptions go to the `CoroutineExceptionHandler`, not the caller; use `async { }.await()` or an explicit handler
- `runBlocking` called on the main/UI thread — blocks the thread and causes ANRs or deadlocks in Android/server contexts
- Misusing `GlobalScope.launch` — leaks coroutines with no lifecycle bound; use a structured `CoroutineScope`
- `equals()`/`hashCode()` inconsistency on `data class` with mutable fields — using mutable data classes as map keys or set elements produces incorrect lookups after mutation

### Security (Kotlin-specific)
- `ProcessBuilder` / `Runtime.exec()` with user-controlled arguments constructed as a single shell string — command injection; always use the list-of-arguments form, never shell string concatenation
- Deserialization via Java's `ObjectInputStream` — arbitrary code execution on untrusted bytes; prefer `kotlinx.serialization` or Jackson with safe type handling disabled
- Logging of sensitive fields (passwords, tokens, PII) via `toString()` on data classes — data classes auto-generate `toString()` for all fields
- `@Suppress("UNCHECKED_CAST")` without a comment — hides potential `ClassCastException`; require explanation

### JVM Interop
- Kotlin's non-null types are not enforced at JVM bytecode boundaries — Java callers can pass `null` into non-null parameters; add `@NotNull` or runtime checks in public APIs called from Java
- `@Throws(SomeException::class)` required on functions called from Java that throw checked exceptions
