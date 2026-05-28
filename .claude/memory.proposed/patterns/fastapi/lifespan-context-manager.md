---
name: lifespan-context-manager
description: Use @asynccontextmanager lifespan; never on_startup/on_shutdown
metadata:
  type: pattern
  stack: fastapi
slug: lifespan-context-manager
status: established
Owner: "@Shravan Jha"
written_by: seed-patterns
written_at: 2026-05-28
last_verified: 2026-05-28
verified_in_commits: []
recurred_anti: 0
---

# Lifespan Context Manager

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
FastAPI < 0.93 (pre-lifespan); also if you have no startup/shutdown needs (omit entirely).
