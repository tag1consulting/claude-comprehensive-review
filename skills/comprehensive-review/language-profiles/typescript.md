## TypeScript-Specific Review Context

When reviewing TypeScript code, pay particular attention to:

### TypeScript Validation Idioms (Do NOT Flag)
- Type narrowing via `typeof`, `in`, `instanceof`, and discriminated unions — this IS type-safe handling
- `satisfies` operator for validating const shapes against a type — this IS compile-time validation
- `readonly` on fields and arrays — this IS defensive immutability design
- Optional chaining `?.` and nullish coalescing `??` — these ARE null-safe access patterns
- Branded/opaque types (`type UserId = string & { __brand: 'UserId' }`) — this IS invariant enforcement
- `unknown` instead of `any` with a subsequent type guard — this IS safe dynamic handling

### Common TypeScript Bugs
- `any` used to silence the compiler without comment — flag; require narrowing or `unknown`
- `as SomeType` casts that lie to the compiler (not narrowing, just suppression) — flag
- Non-null assertion `!` on values that can realistically be `null`/`undefined` at runtime — flag
- `==` vs `===`: always prefer `===`; the one exception (`x == null`) intentionally matches both `null` and `undefined`
- Floating promises — `async` function return values not `await`ed, not `.catch()`ed, and not returned — unhandled rejections
- `Array.prototype.sort()` on numbers without a comparator — default sort is lexicographic
- `JSON.parse()` return typed as a specific interface without runtime validation — shape not guaranteed
- Stale closures in React `useEffect`/`useCallback` — deps array must include all values read in the closure
- Missing `key` prop (or using array index as key) on dynamically rendered lists
- `useEffect` that subscribes to events, timers, or observables without a cleanup return function
- Type widening: `let x: 'a' | 'b' = value` may widen if `value` is `string`; prefer `as const`

### Security (TypeScript/JavaScript-specific)
- `dangerouslySetInnerHTML={{ __html: userInput }}` / `element.innerHTML = userInput` / `document.write(userInput)` — XSS
- `eval(str)`, `new Function(str)`, `setTimeout(str, delay)` with any dynamic string — code injection
- Prototype pollution: `Object.assign(target, userInput)` / recursive merge of untrusted keys can overwrite `__proto__`
- RegExp with nested or overlapping quantifiers on user-controlled input — ReDoS risk
- `fetch`/`axios` calls without a timeout and without validating response shape before use
- Node.js: `child_process.exec(userInput)` / `spawn('sh', ['-c', userInput])` — command injection; use `execFile` with arg array
- Node.js: `fs.readFile(req.params.path)` without path normalization — directory traversal
- JWT: accepting `alg: "none"`; storing the signing secret in client-side code
- Hardcoded credentials, API keys, or tokens in source files

### Data Flow Trust Boundaries
- `req.body`, `req.query`, `req.params` — untrusted; validate with zod/class-validator before use
- URL hash/fragment, `postMessage` data, `localStorage`/`sessionStorage` — untrusted
- `JSON.parse()` return value — shape is unverified at runtime; use a schema validator
- `process.env.VAR` — trusted source but potentially unset; treat as `string | undefined`
- DOM input values, URL search params, cookie values — untrusted

### Idiomatic TypeScript / React
- Prefer `unknown` over `any` for externally-sourced data; narrow with a type guard before use
- Prefer named interfaces or type aliases over repeated inline shapes
- React: `dispatch` (useReducer) and `setState` (useState) are guaranteed stable — omitting them from deps is intentional and NOT a bug. Ref objects (`useRef` return value) are stable, but `ref.current` is mutable — do not suppress deps warnings involving `ref.current` without context
- `as const` on literal objects and arrays preserves narrowest types and is idiomatic
- Don't flag `// @ts-ignore` or `// @ts-expect-error` if a comment explains the suppression
