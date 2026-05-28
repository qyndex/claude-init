---
name: domain-events
description: Aggregates publish events; subscribers in separate module
metadata:
  type: pattern
  stack: cross
slug: domain-events
status: established
Owner: "@Shravan Jha"
written_by: seed-patterns
written_at: 2026-05-28
last_verified: 2026-05-28
verified_in_commits: []
recurred_anti: 0
---

# Domain Events

## When to use
When ≥ 3 modules need to react to a domain change (user signed up → send email + analytics + create default workspace + bill).

## Canonical example
```ts
// 1. Aggregate publishes
class User {
  static async create(input): Promise<User> {
    const user = new User(input);
    await db.save(user);
    eventBus.publish("user.created", { user });
    return user;
  }
}

// 2. Subscribers (in separate files)
// emails/handlers.ts
eventBus.on("user.created", async ({ user }) => sendWelcomeEmail(user));

// analytics/handlers.ts
eventBus.on("user.created", async ({ user }) => track("signup", user));

// workspaces/handlers.ts
eventBus.on("user.created", async ({ user }) => createDefaultWorkspace(user));
```

## Why
- Decouples emitter from receivers
- New subscribers without touching emitter
- Async fan-out becomes trivial

## When NOT to use
- ≤ 2 receivers → direct function call is simpler
- Synchronous transaction required (events make rollback hard)
