#!/usr/bin/env bash
# Pattern seeding — Round 9 E.
#
# Pre-seeded patterns live in this script as heredocs. Operator runs
# /seed-patterns <stack> to write them into .claude/memory/patterns/<stack>/.
#
# Stacks: nextjs | react-vite | node-api | flask | fastapi | cross | all | auto

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

stack="${1:-}"
FORCE=0
[ "${2:-}" = "--force" ] && FORCE=1

if [ -z "$stack" ]; then
  echo "Usage: bash .claude/scripts/seed-patterns.sh <stack> [--force]"
  echo "  stacks: nextjs | react-vite | node-api | flask | fastapi | cross | all | auto"
  exit 1
fi

# Resolve stacks
if [ "$stack" = "auto" ]; then
  # JUSTIFIED: the redirect drops detect-stacks stderr — an empty result yields no pattern folders below, so seeding simply does nothing rather than aborting on an undetectable stack
  stacks_json=$(bash .claude/scripts/detect-stacks.sh 2>/dev/null)
  echo "Detected: $stacks_json"
  # Map detected → pattern folders
  stacks=$(echo "$stacks_json" | jq -r '.stacks[]' | sed 's/^typescript$/react-vite nextjs node-api/' | sed 's/^python$/flask fastapi/' | tr ' ' '\n' | sort -u | tr '\n' ' ')
  stacks="$stacks cross"
elif [ "$stack" = "all" ]; then
  stacks="nextjs react-vite node-api flask fastapi cross"
else
  stacks="$stack"
fi

DEST=".claude/memory/patterns"
seeded=0
skipped=0

write_pattern() {
  local stack_dir="$1"
  local slug="$2"
  local title="$3"
  local body="$4"

  local path="$DEST/$stack_dir/$slug.md"
  mkdir -p "$(dirname "$path")"

  if [ -f "$path" ] && [ "$FORCE" != "1" ]; then
    skipped=$((skipped + 1))
    return
  fi

  # JUSTIFIED: the redirect and fallback yield "unowned" when no git user is configured — the owner field is cosmetic provenance and must not break seeding
  owner_name="$(git config user.name 2>/dev/null || echo unowned)"
  cat > "$path" <<EOF
---
name: $slug
description: $title
metadata:
  type: pattern
  stack: $stack_dir
slug: $slug
status: established
Owner: "@$owner_name"
written_by: seed-patterns
written_at: $(date -I)
last_verified: $(date -I)
verified_in_commits: []
recurred_anti: 0
---

$body
EOF
  seeded=$((seeded + 1))
}

for s in $stacks; do
  case "$s" in
    nextjs)
      write_pattern nextjs "server-vs-client-components" "Default to RSC; mark 'use client' only at leaf interactivity" '# Server vs Client Components

## When to use
Every new Next.js (App Router) component starts as a Server Component. Only mark `"use client"` at leaf nodes that need browser APIs or hooks (forms, event handlers, useState/useEffect).

## Why
- Smaller client bundle
- Direct DB/API access without intermediate route
- Better SEO via streamed HTML

## Canonical example
```tsx
// app/(app)/dashboard/page.tsx — Server Component (no "use client")
import { getUser } from "@/lib/db";
import { UserMenu } from "./UserMenu";  // imported Client Component

export default async function Dashboard() {
  const user = await getUser();
  return <UserMenu user={user} />;
}
```

## Anti-pattern
`"use client"` on the root layout — kills the entire RSC tree.

## When NOT to use
Pages Router projects; libraries pre-React-18.'
      ;;

    react-vite)
      write_pattern react-vite "lazy-suspense-route-split" "Split routes via React.lazy + Suspense; never at leaves" '# Lazy + Suspense at Route Boundaries

## When to use
Code-split at route boundaries to reduce initial bundle. NEVER at component-tree leaves (causes layout shift).

## Canonical example
```tsx
const Dashboard = React.lazy(() => import("./Dashboard"));
const Settings = React.lazy(() => import("./Settings"));

<Routes>
  <Route path="/dashboard" element={
    <Suspense fallback={<DashboardSkeleton />}>
      <Dashboard />
    </Suspense>
  } />
</Routes>
```

## Anti-pattern
```tsx
// ✗ DO NOT lazy-load every component
const Button = React.lazy(() => import("./Button"));  // causes layout shift
```

## When NOT to use
Components above-the-fold or those rendered hundreds of times — eager-load.'
      ;;

    node-api)
      write_pattern node-api "layered-architecture" "router → controller → service → repository; controllers never touch DB" '# Layered Architecture

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
Controller directly running SQL queries (`router → DB`); skips testability + reuse.'
      ;;

    flask)
      write_pattern flask "application-factory" "create_app() returns Flask instance; no module-level app" '# Application Factory

## When to use
Every Flask project. Enables multi-env config, testing fixtures, and lazy initialization.

## Canonical example
```python
# app/__init__.py
from flask import Flask

def create_app(config_name: str = "production") -> Flask:
    app = Flask(__name__)
    app.config.from_object(f"app.config.{config_name.title()}Config")

    # Initialize extensions
    from .extensions import db, migrate, login_manager
    db.init_app(app)
    migrate.init_app(app, db)
    login_manager.init_app(app)

    # Register blueprints
    from .auth import auth_bp
    from .api.v1 import api_v1_bp
    app.register_blueprint(auth_bp)
    app.register_blueprint(api_v1_bp)

    return app
```

```python
# wsgi.py — production entry
from app import create_app
app = create_app("production")
```

## Anti-pattern
`app = Flask(__name__)` at module top level — breaks tests, breaks multi-env, breaks SocketIO mounting order.

## When NOT to use
Never — this is non-negotiable for new Flask projects.'
      ;;

    fastapi)
      write_pattern fastapi "lifespan-context-manager" "Use @asynccontextmanager lifespan; never on_startup/on_shutdown" '# Lifespan Context Manager

## When to use
Every FastAPI app needing startup/shutdown logic. The `on_startup`/`on_shutdown` decorators are deprecated.

## Canonical example
```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
from sqlalchemy.ext.asyncio import create_async_engine

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    app.state.engine = create_async_engine(settings.database_url)
    yield
    # Shutdown
    await app.state.engine.dispose()

app = FastAPI(lifespan=lifespan)
```

## Anti-pattern
```python
# ✗ Deprecated
@app.on_event("startup")
async def startup():
    app.state.engine = create_async_engine(...)
```

## When NOT to use
FastAPI < 0.93 (pre-lifespan); also if you have no startup/shutdown needs (omit entirely).'
      ;;

    cross)
      write_pattern cross "repository-pattern" "DB access behind an interface; business logic depends on the interface" '# Repository Pattern

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
Service directly invokes `prisma.user.findUnique(...)` — couples business code to the ORM.'
      write_pattern cross "result-type" "Use Result<T,E> for expected failures; exceptions for unexpected" '# Result Type

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
- Languages that idiomatically use exceptions (Python, Java) — be careful'
      write_pattern cross "domain-events" "Aggregates publish events; subscribers in separate module" '# Domain Events

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
- Synchronous transaction required (events make rollback hard)'
      ;;
  esac
done

# Update MEMORY.md index
if [ "$seeded" -gt 0 ]; then
  for f in $(find .claude/memory/patterns -name '*.md' -not -name '0000-template.md' | sort); do
    name=$(basename "$f" .md)
    stack_dir=$(basename "$(dirname "$f")")
    desc=$(grep -E '^description:' "$f" | head -1 | sed 's/description:[[:space:]]*//' | head -c 80)
    # JUSTIFIED: the muted grep tests whether the pattern is already indexed; a non-match (or absent MEMORY.md) is the trigger to append the index line, which is the intended behavior
    grep -q "$name" .claude/memory/MEMORY.md 2>/dev/null || \
      echo "- [$stack_dir/$name]($(echo "$f" | sed 's|^\.claude/memory/||')) — $desc" >> .claude/memory/MEMORY.md
  done
fi

echo
echo "Seeded: $seeded patterns"
echo "Skipped (already exist): $skipped patterns"
[ "$seeded" -gt 0 ] && echo "Updated .claude/memory/MEMORY.md index"
