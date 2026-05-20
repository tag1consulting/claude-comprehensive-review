## Perl-Specific Review Context

When reviewing Perl code, pay particular attention to:

### Perl Validation Idioms (Do NOT Flag)
- `use strict; use warnings;` at the top of every script/module — required baseline; flag its absence, not its presence
- `local $/` set to `undef` for slurp mode — idiomatic file-read pattern; not global pollution when lexically scoped with `local`
- `die "message\n"` — the trailing `\n` suppresses file/line number in the message; intentional in user-facing scripts
- `Carp::croak` / `Carp::confess` from library code — idiomatic error reporting from the caller's perspective

### Common Perl Bugs
- Missing `use strict; use warnings;` — without these, undeclared variables and many runtime errors are silently ignored
- `my` vs `local` vs bare variable: `my` creates a lexical; `local` temporarily overrides a global; a bare `$var` without `my` or `local` is a global (forbidden under `strict`)
- String vs numeric comparison: `==` / `!=` / `<` / `>` are numeric; `eq` / `ne` / `lt` / `gt` are string — mixing them silently coerces the operand
- `@array` in scalar context returns the count, not the last element — use `$array[-1]` for the last element
- `unless`/`until` with complex conditions — negation of compound conditions is easy to get wrong; prefer `if !(...)`
- Hash slice `@hash{@keys}` vs `$hash{$key}` — a common typo with silent behaviour change

### Security (Perl-specific)
- Taint mode (`-T` flag) — recommended for any script that handles user input (CGI, web, command-line); untaints data explicitly before use in shell calls, file opens, or string-eval
- `system()` / `open()` / backtick calls with a single string argument that contains user-controlled data — passes through the shell; use the list form to avoid shell injection
- Regex injection: `/$user_input/` — a user-controlled pattern can cause ReDoS or match unintended input; validate or `quotemeta()` before interpolating user data into a regex
- String-form `eval` on user-controlled input — executes arbitrary code; use block-form `eval { }` for exception handling instead
- CPAN dependencies: verify module signatures and check for known vulnerabilities; prefer `cpanm` with `--verify` or Carton with a locked `cpanfile.snapshot`

### Idiomatic Perl
- `use Scalar::Util qw(blessed reftype looks_like_number)` — idiomatic type-checking utilities; prefer over hand-rolled checks
- `open my $fh, '<', $filename or die "..."` — three-argument open is required; two-argument open is a security risk
- `chomp` before processing user input or file lines — removes the trailing newline without altering the rest of the string
