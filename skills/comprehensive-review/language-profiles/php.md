## PHP-Specific Review Context

When reviewing PHP code, pay particular attention to:

### PHP Validation Idioms (Do NOT Flag)
- `htmlspecialchars($s, ENT_QUOTES, 'UTF-8')` on output — this IS XSS-safe escaping
- PDO `prepare()`/`execute()` or mysqli `bind_param()` — these ARE SQL-injection-safe patterns
- Drupal: `$connection->query($sql, [':placeholder' => $val])` — the placeholder array IS parameterized
- Drupal: `Html::escape()`, `Xss::filter()`, `Xss::filterAdmin()` on rendered output — XSS-safe in the correct context
- Drupal: `'#plain_text' => $value` in render arrays — `Html::escape()` is applied automatically at render time; this IS XSS-safe
- `declare(strict_types=1)` at file top — this IS a type-coercion guardrail; do not flag it
- `===` / `!==` comparisons — this IS strict type-safe comparison

### Common PHP Bugs
- Loose `==` comparison across types: `0 == "string"` is `true` in PHP ≤ 7; `0 == "0"` is `true` in all versions — use `===`
- `in_array($needle, $haystack)` without the third argument `true` — uses loose comparison; pass `true` for strict
- `switch` uses loose comparison — prefer `match` (PHP 8.0+) for strict equality
- Missing `??` / null guards on array key lookups — `$arr['k']` emits notice if key absent; use `$arr['k'] ?? default`
- Float comparison with `==` — floats are inexact; use `abs($a - $b) < PHP_FLOAT_EPSILON`
- `foreach ($array as &$value)` without `unset($value)` after the loop — reference leaks into enclosing scope
- Missing return-type declarations on new functions — type mismatch bugs silently return null
- `count()` on non-countable (PHP 7.2+ throws TypeError) — guard with `is_array()` or `is_countable()`

### Security (PHP-specific)
- SQL injection: string concatenation into `mysqli_query()` or `PDO::query()` — use prepared statements
- XSS: `echo $var` / `print $var` without `htmlspecialchars()` or Drupal escape wrapper — flag all raw output
- `unserialize()` on any user-controlled or externally-sourced string — object injection / RCE; use `json_decode()` instead
- File inclusion: `include`, `require`, `require_once`, `include_once` with any variable derived from input — LFI/RFI
- `eval()` or `assert(string)` with dynamic or user-controlled content — code injection
- `preg_replace()` with the `/e` modifier (PHP < 7.0 feature, still seen in legacy) — arbitrary code execution
- `extract($_REQUEST)` / `extract($_GET)` / `extract($_POST)` — variable injection into local scope
- Weak password hashing: `md5()` / `sha1()` / unsalted `hash()` for passwords — use `password_hash()` with `PASSWORD_BCRYPT` or `PASSWORD_ARGON2ID`
- Insecure random: `rand()` / `mt_rand()` for tokens, nonces, or CSRF values — use `random_bytes()` / `random_int()`
- File uploads: trusting `$_FILES['f']['type']` (client-supplied MIME) or file extension alone — verify MIME from file content

### Data Flow Trust Boundaries
- `$_GET`, `$_POST`, `$_REQUEST`, `$_COOKIE`, `$_FILES` — untrusted; validate and sanitize before use
- `$_SERVER['REQUEST_URI']`, `$_SERVER['HTTP_HOST']`, `$_SERVER['HTTP_REFERER']` — untrusted (can be spoofed)
- Drupal: `\Drupal::request()->query->get()`, `->request->get()`, `->headers->get()` — untrusted
- Drupal: entity and config object loads are trusted data sources, but their rendered output must still be escaped
- File paths assembled from any user-provided segment — untrusted; reject `..` traversal and absolute paths

### Drupal-Specific Patterns (if applicable)
- `.module`, `.theme`, `.inc` file extensions are Drupal hook files — `hook_*_alter()` and similar functions are Drupal conventions, not "unused functions"
- Prefer `t()` / `$this->t()` with `@variable`, `%variable`, or `:variable` placeholders — these are auto-escaped
- Deprecated (D7): `check_plain()` — use `Html::escape()` in D8+
- Deprecated (D7): `db_query()` / `db_select()` — use `\Drupal::database()` or inject `\Drupal\Core\Database\Connection`
- Entity access: use `$entity->access('view', $account)` rather than inline permission checks
- Form API: `::validateForm()` should not be skipped; flag submit handlers that bypass validation entirely
- Render arrays: `#markup` is filtered; raw concatenation into `#children` or render callbacks is not safe
- Caching: flag missing cache contexts (`#cache['contexts']`) when render output varies by user, role, or URL

### Idiomatic PHP
- Root-namespace `\` prefix on built-in classes inside namespaced files (e.g., `\DateTime`, `\Exception`) is idiomatic — do not flag
- Prefer `declare(strict_types=1)` and typed properties (PHP 7.4+) for new code; do not flag their absence in legacy files
- Null coalescing `??` and null coalescing assignment `??=` are idiomatic PHP 7+ patterns
- Do not flag PSR-2/PSR-12 style issues (brace placement, spacing) — code sniffers handle these
