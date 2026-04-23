## Java-Specific Review Context

When reviewing Java code, pay particular attention to:

### Common Bugs
- `NullPointerException` — dereference of a field or return value that may be `null`; prefer `Optional<T>` for nullable returns
- `equals`/`hashCode` contract violation — overriding one without the other breaks `HashMap`/`HashSet` behavior
- `==` used for `String` or object comparison instead of `.equals()`
- `ArrayList` returned from a method being mutated by the caller — return `Collections.unmodifiableList()` or a copy
- `int` arithmetic on values that may overflow `Integer.MAX_VALUE` — use `long` or `Math.addExact`
- `Iterator.remove()` not called when removing during iteration — use the iterator's own `remove()`, not the collection's
- Unchecked `ClassCastException` from raw type usage or unchecked casts

### Security
- XML parsing without disabling external entity resolution (XXE) — always set `XMLConstants.FEATURE_SECURE_PROCESSING` or disable `DOCTYPE` declarations
- `ObjectInputStream.readObject()` on untrusted data — Java deserialization is a known RCE vector; use safe alternatives
- `Runtime.exec()` or `ProcessBuilder` with user-controlled input — command injection; use argument arrays, never shell strings
- `MessageDigest` with `MD5`/`SHA-1` for security-sensitive hashing — use `SHA-256` or stronger
- Hardcoded credentials or secrets in source — externalize to environment or secrets manager
- SQL string concatenation — always use `PreparedStatement` with `?` placeholders

### Idiomatic Java
- Prefer `final` fields and local variables to signal immutability intent
- Use try-with-resources (`try (InputStream is = ...)`) for `Closeable` resources — never rely on `finally` for close
- Prefer `List.of()` / `Map.of()` (Java 9+) for immutable collections over `Arrays.asList`
- `Optional` should not be used as a field type or method parameter — only as a return type
- Prefer `Stream` pipeline over manual `for` loops for collection transformations
- `@Override` annotation on all overriding methods — catches signature mismatches at compile time

### Do NOT flag
- Checked exceptions declared in `throws` clauses — required by the Java spec for non-`RuntimeException` exceptions
- Verbose getter/setter patterns — idiomatic Java; flag only when a record or Lombok would materially simplify
