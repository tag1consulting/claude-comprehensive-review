## YAML-Specific Review Context

When reviewing YAML files, pay particular attention to:

### YAML Parser Quirks (Do NOT Flag as Bugs When Used Intentionally)
- Quoted strings (`"yes"`, `'no'`) — quoting a YAML 1.1 boolean keyword to force string type is intentional and correct
- Block scalars (`|`, `>`) for multi-line strings — idiomatic; do not prefer folded vs literal without context
- Anchors (`&anchor`) and aliases (`*anchor`) for deduplication — intentional when the referenced block is truly identical

### Common YAML Bugs
- YAML 1.1 boolean trap: unquoted `yes`, `no`, `on`, `off`, `true`, `false` (and all-caps variants) are booleans in many parsers; strings must be quoted — `"yes"`, `"no"`, etc.
- Unquoted version numbers: `version: 1.10` parses as float `1.1` in some parsers; always quote: `version: "1.10"`
- Accidental tab characters — YAML forbids tabs for indentation; tabs cause parser errors on some implementations
- Duplicate keys in the same mapping — behaviour is parser-defined (last wins, first wins, or error); always use unique keys
- Anchor/alias cycles — some parsers do not detect circular anchors and loop indefinitely; flag deep or recursive alias chains
- Missing `---` document separator in multi-document streams — required when concatenating documents

### Security (YAML-specific)
- `yaml.load(data)` without `Loader=yaml.SafeLoader` (Python PyYAML) — allows arbitrary object deserialisation and RCE; always use `yaml.safe_load()` or `Loader=yaml.SafeLoader`
- YAML deserialisers in other languages with equivalent "unsafe" load functions (e.g. `yaml.UnmarshalStrict` in Go does not protect against type confusion) — flag non-safe loaders
- Secrets in plain text within YAML config files (API keys, passwords, tokens) — require reference to a secret store or environment variable substitution
- GitHub Actions: `${{ github.event.pull_request.title }}` or similar user-controlled expressions interpolated directly into `run:` steps — script injection; wrap in an environment variable instead

### Framework-Specific Patterns
- **GitHub Actions**: `on: push` without branch filters runs on every branch including forks; `permissions:` should be as narrow as possible; `GITHUB_TOKEN` write permissions should be explicit
- **Kubernetes**: `latest` image tags are non-reproducible; `resources.limits` and `resources.requests` should always be set; `hostNetwork: true` / `privileged: true` require justification
- **docker-compose**: `image: latest` is non-reproducible; bind-mounted host paths (volumes with absolute paths) may expose host filesystem
