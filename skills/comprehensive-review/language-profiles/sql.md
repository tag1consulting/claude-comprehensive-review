## SQL-Specific Review Context

When reviewing SQL files (queries, migrations, stored procedures), pay particular attention to:

### SQL Validation Idioms (Do NOT Flag)
- `COALESCE(col, default)` — correct null-to-default substitution; do not flag as missing null check
- `LEFT JOIN ... WHERE rhs.col IS NULL` — idiomatic anti-join pattern; intentional
- `EXISTS (SELECT 1 FROM ...)` — more efficient than `IN (SELECT ...)` on large sets; do not prefer `IN`
- `TRUNCATE` instead of `DELETE FROM` for full-table wipes in migration scripts — intentional for performance; flag only if referential integrity is at risk

### Common SQL Bugs
- String interpolation / concatenation in application code building SQL — SQL injection; require parameterised queries (`?`, `$1`, named params)
- `NULL` comparison with `=` — `col = NULL` always evaluates to `UNKNOWN`, never `TRUE`; use `IS NULL` / `IS NOT NULL`
- `NOT IN (subquery)` when the subquery can return `NULL` — the entire `NOT IN` evaluates to `UNKNOWN` if any row is `NULL`; use `NOT EXISTS` instead
- `SELECT *` in production queries — fragile against schema changes; select named columns
- Missing index on columns used in `JOIN ON`, `WHERE`, `ORDER BY`, or `GROUP BY` — full table scan risk on large tables
- Implicit type coercion in `WHERE` predicates — `WHERE int_col = '123'` may prevent index use; match literal types to column types

### Migration Safety
- `ADD COLUMN ... NOT NULL` without a `DEFAULT` on a populated table — fails or requires a full table rewrite (depending on database); add a default or backfill before enforcing `NOT NULL`
- `DROP COLUMN` / `DROP TABLE` — irreversible; require a confirmed backup and rollback plan in the migration
- Schema changes that acquire an `ACCESS EXCLUSIVE` lock (e.g. `ALTER TABLE ADD COLUMN` in PostgreSQL without a default) — block all reads and writes; schedule for low-traffic windows
- Renaming a column without updating application code that references the old name — runtime errors post-deploy; coordinate with code changes

### Security (SQL-specific)
- Dynamic SQL in stored procedures via `EXECUTE` / `EXEC sp_executesql` with concatenated input — SQL injection; use parameterised dynamic SQL
- `GRANT ALL PRIVILEGES` to application database users — over-privileged; application accounts should have only `SELECT`/`INSERT`/`UPDATE`/`DELETE` on required tables
- Plaintext passwords or PII stored without hashing/encryption — flag in schema reviews
