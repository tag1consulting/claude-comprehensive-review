## Scala-Specific Review Context

When reviewing Scala code, pay particular attention to:

### Scala Validation Idioms (Do NOT Flag)
- `Option.fold` / `Option.map` / `Option.getOrElse` — idiomatic null-safe handling; do not prefer `.get`
- `Try { }` wrapping side-effectful operations — idiomatic exception capture; not excessive
- `Either[Error, A]` as a return type — correct explicit error propagation; do not prefer exceptions
- `match` on `sealed trait` / `sealed abstract class` — exhaustive pattern matching; compiler warns on missing cases
- `for`-comprehension over `Future` / `Option` / `Either` — idiomatic monadic chaining; not confusing nesting

### Common Scala Bugs
- `.get` on `Option` — throws `NoSuchElementException` on `None`; use `getOrElse`, `fold`, or pattern match
- `Await.result(future, Duration.Inf)` — blocks the thread indefinitely; use a finite timeout and handle `TimeoutException`
- Implicit conversions that widen types silently — flag `implicit def` that converts between unrelated types without a comment
- `case class` with mutable fields (`var`) used as a map key — `hashCode` changes after mutation, losing the entry
- `Future` inside a `for`-comprehension without `flatMap` awareness — sequential `.map` on `Future` does not parallelise; use `Future.sequence` or parallel `zip`
- Exception thrown inside a `Future` without a recovery — silently fails; add `.recover` or `.recoverWith`

### Security (Scala-specific)
- Shell command constructed from user input as a single string passed to the OS — command injection; use a `Seq[String]` argument form with the process builder, never shell string concatenation
- `ObjectInputStream` on untrusted data — unsafe object materialisation, allows arbitrary code execution; prefer `circe`/`spray-json`/`upickle` with explicit schemas
- Akka actor messages that are mutable — actors passing mutable state between threads cause data races; messages must be immutable (prefer `case class` / `case object`)

### Scala 2 vs Scala 3
- Scala 3 drops procedural syntax (`def f() { }` without `=`) — these are value-discarding expressions, not unit-returning methods; use `def f(): Unit = { }`
- Scala 3 `given`/`using` replaces Scala 2 `implicit val`/`implicit parameter` — do not flag Scala 3 syntax as incorrect when the project targets Scala 3
