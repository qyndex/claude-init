---
name: result-type
description: Use Result<T,E> for expected failures; exceptions for unexpected
metadata:
  type: pattern
  stack: cross
slug: result-type
status: established
Owner: "@Shravan Jha"
written_by: seed-patterns
written_at: 2026-05-28
last_verified: 2026-05-28
verified_in_commits: []
recurred_anti: 0
---

# Result Type

## When to use
For EXPECTED failures (validation, not-found, conflict). Exceptions are for UNEXPECTED (network drop, OOM, bug).

## Canonical example (TS)
```ts
type Ok<T> = { ok: true; value: T };
type Err<E> = { ok: false; error: E };
type Result<T, E> = Ok<T> | Err<E>;

async function getUser(id: string): Promise<Result<User, "not-found" | "db-error">> {
  try {
    const user = await db.query(...);
    if (!user) return { ok: false, error: "not-found" };
    return { ok: true, value: user };
  } catch (e) {
    return { ok: false, error: "db-error" };
  }
}

// callsite
const r = await getUser("123");
if (!r.ok) {
  if (r.error === "not-found") return c.json({}, 404);
  return c.json({}, 500);
}
return c.json(r.value);
```

## Why
- Callers cannot forget to handle errors (TS exhaustiveness)
- Cleaner than try/catch sprawl
- Distinguishes expected (Result.Err) from exceptional (throw)

## When NOT to use
- Truly exceptional (out-of-memory, panic) → throw
- Languages that idiomatically use exceptions (Python, Java) — be careful
