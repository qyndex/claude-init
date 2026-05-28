---
name: repository-pattern
description: DB access behind an interface; business logic depends on the interface
metadata:
  type: pattern
  stack: cross
slug: repository-pattern
status: established
Owner: "@Shravan Jha"
written_by: seed-patterns
written_at: 2026-05-28
last_verified: 2026-05-28
verified_in_commits: []
recurred_anti: 0
---

# Repository Pattern

## When to use
Any non-trivial app with persistent storage. Keeps DB choice swappable and tests fast (in-memory repo).

## Canonical example
```ts
// port
interface UserRepository {
  findById(id: string): Promise<User | null>;
  save(user: User): Promise<void>;
}

// adapter
class PostgresUserRepository implements UserRepository {
  constructor(private pool: Pool) {}
  async findById(id: string): Promise<User | null> {
    const result = await this.pool.query("SELECT * FROM users WHERE id = $1", [id]);
    return result.rows[0] ?? null;
  }
  async save(user: User): Promise<void> { /* INSERT/UPDATE */ }
}

// service depends on the INTERFACE
class UserService {
  constructor(private repo: UserRepository) {}
}

// test
const fakeRepo: UserRepository = {
  findById: async () => ({ id: "1", name: "Alice" }),
  save: async () => {},
};
const service = new UserService(fakeRepo);
```

## Why
- Swap Postgres → SQLite for tests
- Mock the repo without mocking the entire ORM
- Service code reads as business logic, not SQL

## Anti-pattern
Service directly invokes `prisma.user.findUnique(...)` — couples business code to the ORM.
