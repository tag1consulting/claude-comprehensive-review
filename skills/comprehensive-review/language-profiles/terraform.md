## Terraform-Specific Review Context

When reviewing Terraform code, pay particular attention to:

### Terraform Validation Idioms (Do NOT Flag)
- `lifecycle { prevent_destroy = true }` — intentional guard on critical resources; do not flag as unnecessary
- `depends_on` on a module or resource when the dependency is implicit through data sources — sometimes required to force ordering
- `ignore_changes` on tags or metadata managed externally (e.g. by AWS auto-scaling) — intentional drift tolerance
- `for_each = toset([...])` with an explicit set literal — idiomatic; do not prefer `count` without context

### Common Terraform Bugs
- `count` vs `for_each`: `count`-indexed resources produce brittle plans when items are inserted/removed mid-list (indexes shift); prefer `for_each` for collections of named resources
- `depends_on` overuse: explicit `depends_on` on resources that already share a reference creates redundant edges and can mask real dependency problems
- Provider version constraints too loose (`version = ">= 2.0"`) — allows unexpected major-version upgrades; pin with `~>` for minor-version flexibility
- Missing `required_providers` block — implicit provider selection leads to undeclared version use
- `terraform_remote_state` data source without a `defaults` block — plan fails if the remote state is absent (first bootstrap)
- Module outputs referenced before the module has a `depends_on` — can produce empty values during bootstrap

### Security (Terraform-specific)
- `sensitive = false` on outputs that contain secrets (passwords, tokens, private keys) — leaks values in `terraform output` and state files; mark `sensitive = true`
- `local-exec` provisioner with user-controlled strings — command injection; avoid provisioners in favour of cloud-init or user_data
- Unencrypted remote state backend — always enable server-side encryption (e.g. `encrypt = true` for S3)
- `null_resource` / `local-exec` used to work around provider gaps — leaves untracked side effects outside state; flag for review
- IAM policies with `"*"` for both `Action` and `Resource` — overly broad; require justification comment
- Security group rules with `0.0.0.0/0` on inbound SSH (port 22) or RDP (port 3389) — flag unless explicitly justified

### Idiomatic Terraform
- Use `moved` blocks (Terraform ≥ 1.1) instead of destroy-and-recreate when renaming resources
- Prefer `for_each` over `count` for any resource that represents a named logical entity
- Separate `variables.tf`, `outputs.tf`, `main.tf`, and `versions.tf` — do not consolidate in one file
- Use `validation` blocks on `variable` declarations to fail-fast on invalid inputs
- State locking is required for shared workspaces — always configure a DynamoDB table (S3 backend) or equivalent
