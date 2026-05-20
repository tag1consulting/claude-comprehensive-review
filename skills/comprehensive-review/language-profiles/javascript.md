## JavaScript-Specific Review Context

When reviewing JavaScript code, pay particular attention to:

### JavaScript Validation Idioms (Do NOT Flag)
- `x == null` — intentional dual check for both `null` and `undefined`; do not flag in favour of `=== null && === undefined`
- `Promise.allSettled()` — correct when some tasks may fail independently; do not prefer `Promise.all()` without context
- `typeof x !== 'undefined'` — safe global presence check; `x !== undefined` can throw in some contexts
- `Array.isArray(x)` over `instanceof Array` — correct in multi-realm environments

### Common JavaScript Bugs
- `==` vs `===`: type-coercing equality causes subtle bugs (`0 == false`, `'' == false`, `null == undefined`)
- Truthiness traps: `0`, `""`, `NaN`, `[]` (non-empty array), `{}` (non-empty object) have counterintuitive truthiness
- `async` functions that swallow exceptions silently — missing `try/catch` or `.catch()` on returned promise
- Unhandled promise rejections — floating `async` calls with no `await`, no `.catch()`, and no `return`
- `Array.prototype.sort()` without a comparator — default is lexicographic, not numeric
- `var` in block scopes — hoisted to function scope; prefer `const`/`let`
- `this` lost in callbacks — methods passed as callbacks lose their `this` binding; use arrow functions or `.bind()`
- `for...in` on arrays — iterates prototype chain keys, not indexes; use `for...of` or `.forEach()`
- Mutating function arguments that are objects — callers see the mutation; clone if the function should be pure

### Security (JavaScript-specific)
- Dynamic code execution via `eval()`, or passing strings to `setTimeout`/`setInterval` as the first argument — code injection risk; always pass a function reference, never a string
- `innerHTML` / `outerHTML` / `document.write()` with any non-literal string — XSS
- Prototype pollution: `Object.assign(target, untrusted)` / recursive merge without an `Object.create(null)` guard on the target
- `RegExp` with user-controlled pattern — ReDoS if the pattern contains nested quantifiers
- `require()` / dynamic `import()` with user-controlled paths — path traversal / module injection
- Hardcoded API keys, tokens, or credentials in source files
- `npm install` without `--ignore-scripts` on untrusted packages — lifecycle script execution risk

### Data Flow Trust Boundaries
- `req.body`, `req.query`, `req.params` (Express) — untrusted; validate before use
- `event.data` from `postMessage` — untrusted; always verify `event.origin`
- `localStorage` / `sessionStorage` / cookie values — untrusted; can be modified by the user
- URL hash / `window.location.search` — untrusted; sanitize before DOM insertion

### Idiomatic JavaScript
- Prefer `const` by default; `let` for rebindable values; avoid `var`
- Use `??` (nullish coalescing) rather than `||` when `0` or `""` are valid values
- Prefer `Promise`-based APIs over callback-based equivalents for new code
- `Object.freeze()` at module boundary for constants to prevent accidental mutation
