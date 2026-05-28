---
paths:
  - "src/api/**/*"
  - "src/server/**/*"
  - "src/services/**/*"
  - "src/db/**/*"
  - "src/queries/**/*"
  - "migrations/**/*"
  - "alembic/**/*"
  - "prisma/**/*"
  - "drizzle/**/*"
  - "**/*.sql"
---

# Backend rules

> Loaded only when Claude is editing API / service / data-layer code.

## API design

- **Every endpoint has an explicit permission check.** No implicit trust. The check appears at the top of the handler, before any business logic.
- **Validate input at the boundary.** Use Zod / Pydantic / Joi / similar — never trust raw request bodies in handlers.
- **Return typed responses.** No bare `{ ok: true }` — define a response schema and use it.
- **Errors are typed too.** Don't return `500: Internal Server Error` for everything — use the spec's error codes.
- **Idempotency** for any state-changing endpoint that a client might retry: idempotency key in header or natural-key-deduped writes.

## Database

- **Parameterized queries only.** Never string-concat user input into SQL. If you must use raw SQL, use the driver's parameter binding, not template literals.
- **Migrations follow the expand/contract pattern** for any production change (see `.claude/skills/db-migration/SKILL.md`). The four phases — expand → backfill → cutover → contract — each ship in separate deploys. Single-deploy schema changes are only acceptable for development or T3 internal-only services. **NEVER do `forward-only`** on a live table — write a reverse migration unless data loss is acceptable and documented in an ADR.
- **No `SELECT *`.** Name the columns. Indexes break silently with `*`.
- **Every foreign key has an index** on the referencing column. Postgres / MySQL don't add this automatically.
- **N+1 is a bug, not a style issue.** Use the ORM's eager-load / `Include` / `populate` / `join` features.
- **Migrations run with explicit lock awareness.** For `ALTER TABLE` on large tables, use `ALTER ... CONCURRENTLY` (Postgres) or pt-online-schema-change (MySQL).

## Auth & secrets

- **Passwords:** bcrypt or argon2id only. No MD5, SHA1, or unsalted SHA256.
- **Sessions:** rotate on privilege change. Bind to user agent if practical.
- **Tokens:** short-lived access tokens + refresh; never embed long-lived secrets in client code.
- **Rate limiting** on every authentication endpoint (`/login`, `/password-reset`, `/signup`, `/oauth/token`).
- **Logs never contain:** password, raw session token, API key, full credit card, full SSN, raw OAuth refresh token. Mask at the source.

## Observability

- **Every endpoint emits at least one structured log** with: timestamp, request id, user id (if authenticated), endpoint, duration_ms, status.
- **Errors include a stack trace, the inbound request id, and any business identifiers** — but never PII.
- **Latency budgets**: P95 < 200ms read, < 500ms write. Anything slower documents why in the spec.

## Concurrency

- **No silent assumptions about single-process.** If two workers can run, design for it: `SELECT FOR UPDATE`, advisory locks, or queue-based serialization.
- **No global mutable state in handlers.** Use a request-scoped context.
