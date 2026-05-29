# Org security policy — example template
#
# HOW TO USE THIS FILE
# --------------------
# 1. Copy this file to one of the paths below (pick the scope that fits):
#
#      ~/.claude/claude-security-guidance.md          — user-wide (all repos)
#      <repo>/.claude/claude-security-guidance.md     — project-wide (commit this)
#      <repo>/.claude/claude-security-guidance.local.md  — local overrides (gitignore this)
#
# 2. Replace the placeholder examples with rules specific to YOUR codebase.
#    Good rules = things the model CANNOT infer on its own:
#      - "use db.replica for reads, db.primary for writes" (your topology)
#      - "wrap user URLs with safe_request() before fetching" (your helper)
#      - "never log the `ssn` or `tax_id` fields" (your data classification)
#    Bad rules = generic OWASP advice the model already knows:
#      - "sanitize user input" (already built-in)
#      - "don't hardcode secrets" (already built-in)
#
# 3. Delete any section that is not relevant to your stack. An empty or
#    missing section is better than placeholder text that hasn't been filled in.
#
# BUDGET: all three files are concatenated (user → project → project-local)
# up to a combined 8 KB ceiling. If you exceed 8 KB, project-local rules are
# dropped first (user-wide rules are preserved).
#
# This file is a TEMPLATE — it is never auto-loaded by either comprehensive-review
# or security-guidance because the loaders match the filename exactly
# (claude-security-guidance.md / claude-security-guidance.local.md only).

# ───────────────────────────────────────────────────────────────────
# DATA ACCESS
# ───────────────────────────────────────────────────────────────────
# Rules about which data stores, replicas, or shards to use — and
# when direct access is forbidden in favor of a layer/wrapper.

## Database routing

- Read queries MUST use the replica connection (`db.replica`), never
  `db.primary`. Primary is reserved for writes only.
- Queries against the `payments` or `billing` tables MUST go through
  `billing.get_db_connection()`, which enforces row-level tenant isolation.
  Direct table access is prohibited outside that module.

## Multi-tenancy / tenant isolation

- Every query against tenant-scoped tables MUST include a `tenant_id`
  predicate sourced from the authenticated session, not from user input.
  Derive it from `auth.current_tenant()`.

# ───────────────────────────────────────────────────────────────────
# AUTHENTICATION, AUTHORIZATION & SECRETS
# ───────────────────────────────────────────────────────────────────
# Rules about token sources, permission checks, and where credentials
# must come from. Not covered here: hardcoded secrets (built-in check).

## Token usage

- Background jobs and async workers MUST NOT use the user-context auth
  token (`request.user.token`). They must obtain service-account
  credentials via `auth.get_service_account_token(service_name)`.
- Internal service-to-service calls MUST use the service mesh mTLS
  credentials, not a bearer token from the user session.

## Secret sourcing

- Secrets and API keys MUST be retrieved at runtime from the secrets
  manager via `secrets.get(key_name)`. Hardcoding values or reading from
  environment variables outside the approved bootstrap paths is prohibited.

# ───────────────────────────────────────────────────────────────────
# INJECTION & SSRF
# ───────────────────────────────────────────────────────────────────
# Rules about approved wrappers for operations that accept user-controlled
# input. The model already knows these vulnerability classes exist; this
# section tells it which project-specific wrappers to enforce.

## Outbound HTTP with user-controlled URLs

- Calls to `requests.get(url)`, `httpx.get(url)`, or any HTTP client
  where `url` is user-controlled MUST use the SSRF-allowlist wrapper:
  `net.safe_request(url, ...)`. Direct calls are prohibited outside
  `net/safe_request.py`.

## Shell execution

- Any `subprocess.run` / `subprocess.Popen` call that incorporates
  user-provided values MUST use a list argument form (never `shell=True`)
  and MUST pass the value through `shlex.quote()` if string interpolation
  is unavoidable. Flag any `shell=True` usage with user-derived content.

# ───────────────────────────────────────────────────────────────────
# DEPENDENCIES & SUPPLY CHAIN
# ───────────────────────────────────────────────────────────────────
# Banned packages, required pinning policies, or internal forks that
# must be used instead of upstream.

## Banned packages

- `yaml.load()` without `Loader=` is prohibited; use `yaml.safe_load()`.
- The `pickle` module must not be used to deserialize data from any
  network source or user upload.

## Internal forks

- Use `acme/requests-oauthlib` (our fork with proxy support) instead of
  the upstream `requests-oauthlib` package.

# ───────────────────────────────────────────────────────────────────
# LOGGING & DATA HANDLING
# ───────────────────────────────────────────────────────────────────
# Fields that must never appear in logs, error messages, or responses —
# and rules about where sensitive data is permitted to flow.

## PII and regulated data

- The fields `ssn`, `tax_id`, `date_of_birth`, and `full_account_number`
  MUST NOT appear in log statements, error messages, exception stack
  traces, or API responses. Use masked representations (`****1234`) when
  a display value is needed.
- Health and medical record fields (any column in the `health_records`
  table) are subject to HIPAA — they must not leave the data tier except
  through the approved export API in `hipaa/export.py`.

## Error responses

- Exception messages returned to external callers MUST pass through
  `errors.sanitize(e)` before serialization. Never include raw exception
  messages, stack traces, or internal paths in API error responses.
