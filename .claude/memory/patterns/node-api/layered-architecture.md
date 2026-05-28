---
name: layered-architecture
description: router → controller → service → repository; controllers never touch DB
metadata:
  type: pattern
  stack: node-api
slug: layered-architecture
status: established
Owner: "@Shravan Jha"
written_by: seed-patterns
written_at: 2026-05-28
last_verified: 2026-05-28
verified_in_commits: []
recurred_anti: 0
---

# Layered Architecture

## When to use
Any Node.js API beyond a single endpoint. Separates HTTP concerns from business logic from data.

## Canonical layers
- **Router**: HTTP method + path + middleware
- **Controller**: parse request, call service, format response
- **Service**: business logic; no Request/Response types
- **Repository**: DB access; one method per query

## Example
```ts
// router
app.post("/users", zValidator("json", UserCreate), createUserController);

// controller
async function createUserController(c) {
  const input = c.req.valid("json");
  const user = await userService.create(input);
  return c.json(user, 201);
}

// service
class UserService {
  constructor(private repo: UserRepository) {}
  async create(input: UserCreateInput): Promise<User> {
    if (await this.repo.exists(input.email)) throw new ConflictError();
    return this.repo.insert(input);
  }
}

// repository
class UserRepository {
  async exists(email: string): Promise<boolean> { /* SQL */ }
  async insert(input: UserCreateInput): Promise<User> { /* SQL */ }
}
```

## Anti-pattern
Controller directly running SQL queries (`router → DB`); skips testability + reuse.
