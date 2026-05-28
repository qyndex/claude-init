---
name: db-migration
description: Expand/contract pattern for zero-downtime database schema changes. Replaces the (wrong) "forward-only by default" rule. The four-phase pattern: expand → backfill → cutover → contract.
when_to_use: A schema change is needed on a live database. Any DDL touching tables in production. User says "add a column", "rename a column", "change column type", "drop a column", "migration".
allowed-tools: Read, Glob, Grep, Edit, Write, Bash
model: opus
---

# DB Migration — Expand / Contract

Zero-downtime schema changes require the four-phase pattern. A single "forward-only migration" deploy is wrong for any non-trivial change at scale.

## The four phases

```
Phase A — EXPAND
  - Add new schema element (column, table, index) — additive only
  - Old code continues to work (it doesn't see the new element)
  - Deploy and verify no errors

Phase B — DUAL-WRITE / BACKFILL
  - New code writes to BOTH old and new (dual-write)
  - Backfill historical data into the new element (batched, off-peak)
  - Old code still reads the old element

Phase C — CUTOVER (read switch)
  - New code reads from the new element
  - Old code still writes the old element
  - Monitor for divergence; verify the read path is correct

Phase D — CONTRACT
  - Remove dual-write; new code writes only the new element
  - Drop the old element (column / table) — separate deploy
  - Update the schema docs
```

## Per-change patterns

### Add a column
- A: `ALTER TABLE x ADD COLUMN new_col TYPE NULL` (NULL allowed; no default to avoid table rewrite on big tables)
- B: write to both old and new (if replacing); or just start using new
- C: read from new
- D: drop old (if applicable)

### Rename a column
- A: `ALTER TABLE x ADD COLUMN new_name TYPE` (add new)
- B: dual-write old + new; backfill (UPDATE x SET new_name = old_name in batches)
- C: read switches to new
- D: drop old, rename if desired (`ALTER COLUMN ... RENAME` if portable)

### Change a column type
- A: add new typed column (`alter table x add column new_col NEW_TYPE`)
- B: dual-write with conversion; backfill
- C: read from new
- D: drop old

### Split a table
- A: create new tables
- B: dual-write to new tables; backfill
- C: read switches to new tables
- D: drop old table

### Drop a column
- A: stop reading from it (code change first)
- B: stop writing to it (next deploy)
- C: verify no references
- D: drop the column

## Per-DB specifics

### Postgres
- **`ALTER TABLE ADD COLUMN` is fast IF no default + NULL allowed.** Avoid `NOT NULL DEFAULT 'x'` on big tables — it rewrites.
- **Concurrent indexes**: `CREATE INDEX CONCURRENTLY` — doesn't block writes.
- **Long-running migrations**: use `lock_timeout` and `statement_timeout` to avoid blocking pile-ups.
- **Backfill**: `UPDATE ... WHERE id BETWEEN N AND N+1000` in batches; commit per batch.

### MySQL
- **`pt-online-schema-change`** for big tables (Percona toolkit).
- **`gh-ost`** for low-impact schema changes (GitHub's tool).
- Native `ALGORITHM=INPLACE, LOCK=NONE` available for some changes in MySQL 8.

### Aurora / DynamoDB / Mongo / etc.
- Apply the same expand/contract logic; the primitives differ.

## CI gates

- Migration files require a corresponding **reverse migration** OR explicit "no-rollback; data-loss" tag
- Migrations touching large tables (>100k rows) require **`CONCURRENTLY` or pt-osc/gh-ost**
- Phase-A and Phase-D are **separate PRs** (don't combine; each deploys independently)
- Spec's Rollout section lists the four phases with target ship dates

## Hard rules

- **Never combine phases in one deploy.** Each phase is a separate code change + deploy + verify cycle.
- **Always have a reverse migration** for Phase A and Phase D (Phase B/C are code-only).
- **Backfill in batches.** Big single-transaction backfills lock tables.
- **Monitor during cutover.** Watch the read/write divergence at Phase C.
- **Document.** Each migration touches an ADR explaining why.

## References

- Square Engineering — "Zero downtime migrations" (canonical)
- Stripe — "Online schema migrations" blog series
- gh-ost README — https://github.com/github/gh-ost
- See also: `/upgrade` command, `.claude/rules/backend.md`
