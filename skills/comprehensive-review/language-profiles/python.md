## Python-Specific Review Context

When reviewing Python code, pay particular attention to:

### Python Validation Idioms (Do NOT Flag)
- `try/except SpecificError` with `logger.exception(...)` or `raise` — this IS error handling
- `if __name__ == "__main__":` guard — this IS correct entry-point isolation
- `@dataclass` with `field(default_factory=list)` / `field(default_factory=dict)` on mutable fields — this IS safe mutable-default handling
- `with open(...) as f:` / `with contextlib.suppress(...)` — this IS resource management
- Type hints in scripts and tests are optional; only flag missing hints on public library API surfaces

### Common Python Bugs
- Mutable default arguments: `def f(x=[])` or `def f(x={})` — the default is shared across calls; use `None` and assign inside
- Late binding in loop closures: `[lambda: i for i in range(3)]` — all lambdas capture the same `i`; use `lambda i=i: i`
- `is` vs `==` — use `is` only for `None`, `True`, `False`, and sentinel objects; use `==` for value comparison
- Bare `except:` or `except Exception:` that swallows errors silently — require logging or re-raise
- Integer division: `/` always returns float in Python 3; flag if code assumed integer truncation (Py2 port)
- Shadowing builtins: `list`, `dict`, `id`, `type`, `input`, `filter` as variable/parameter names
- Mutating a collection while iterating over it — iterate a copy or use a list comprehension
- `threading.Thread` / `concurrent.futures` without joining or propagating exceptions from workers

### Security (Python-specific)
- `os.system()` / `subprocess.run(..., shell=True)` with any non-literal argument — command injection; use `shell=False` with a list
- `eval()` / `exec()` on untrusted or externally-derived strings — RCE
- `pickle.loads()` / `shelve` / `marshal.loads()` on untrusted data — arbitrary code execution; use `json` instead
- `yaml.load(data)` without `Loader=yaml.SafeLoader` — RCE via YAML deserialization
- SQL via f-string or `%` format: `f"SELECT * FROM t WHERE id={uid}"` — SQL injection; use parameterized queries
- `tempfile.mktemp()` — TOCTOU race; use `tempfile.mkstemp()` or `NamedTemporaryFile`
- `ssl._create_unverified_context()` or `verify=False` in `requests` — disables cert verification
- `hashlib.md5` / `hashlib.sha1` for passwords or security tokens — use `hashlib.pbkdf2_hmac` or `bcrypt`/`argon2`
- Django: raw queries via `.extra()`, `RawSQL()`, or `cursor.execute(f"...")` — use ORM or `%s` placeholders
- Django: `@csrf_exempt` on views that modify state — require justification comment
- Flask: `render_template_string(user_input)` — server-side template injection

### Data Flow Trust Boundaries
- `request.args`, `request.form`, `request.json`, `request.files` — untrusted; validate before use
- `sys.argv`, environment variables from user-controlled CI context — untrusted
- ORM fields populated from deserialized request data — untrusted until validated by form/serializer
- File paths derived from request parameters — untrusted; reject `..` traversal and absolute paths
- `subprocess` stdout from external tools — untrusted; validate before passing to further shell calls

### Idiomatic Python
- EAFP (try/except) is idiomatic; don't flag it in favor of LBYL unless performance-critical
- Prefer `pathlib.Path` over `os.path` string concatenation for new code
- Prefer f-strings over `%` / `.format()` for readability in non-SQL contexts
- Do not flag PEP 8 whitespace, line-length, or import order — linters (`flake8`, `ruff`, `black`) handle these
- Generator expressions are idiomatic for lazy evaluation; don't flag in favor of list comprehensions
