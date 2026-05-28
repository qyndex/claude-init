---
name: fastapi
description: Use when project is FastAPI (Python async web framework). Covers Pydantic v2 models, dependency injection via Depends, async SQLAlchemy 2.x, lifespan context manager, BackgroundTasks vs Celery, routers per feature. Round 9 B.
when_to_use: Atlas detects FastAPI; user edits routers/, main.py, app/api/; user mentions Pydantic, Depends, async sqlalchemy, lifespan, OpenAPI.
model: sonnet
disable-model-invocation: false
last_verified: 2026-05-28
---

# FastAPI

## Mandate

Enforce typed-everywhere Pydantic v2, dependency injection via `Depends()`, async SQLAlchemy 2.x patterns, modern lifespan (NOT `on_startup`/`on_shutdown`), and BackgroundTasks-vs-Celery decision discipline.

## Decisions encoded

- **Pydantic v2 only.** v1 patterns (e.g., `BaseModel.dict()`) are anti-patterns; use `model_dump()`.
- **Every endpoint declares `response_model=`.** Untyped responses → OpenAPI lies.
- **Request bodies are Pydantic classes.** Never `dict` or `Body()` without a model.
- **Dependency injection via `Depends()`.** No module-level state for DB session / current user / settings.
- **Routers per feature.** `APIRouter(prefix="/users", tags=["users"])`; `main.py` only mounts routers.
- **`@asynccontextmanager` lifespan.** Deprecated `on_startup`/`on_shutdown` are forbidden.
- **`BackgroundTasks` for fire-and-forget ≤ 30s; Celery/RQ for retries, scheduling, or > 30s.**
- **Async SQLAlchemy 2.x.** `select(User).where(...)` style — NOT legacy Query.

## Project structure

```
app/
├── main.py              # FastAPI() instance, lifespan, router mounts
├── api/
│   └── v1/
│       ├── __init__.py  # APIRouter(prefix="/v1")
│       ├── users.py
│       ├── auth.py
│       └── billing.py
├── core/
│   ├── config.py        # Pydantic Settings
│   ├── deps.py          # Depends() factories
│   ├── security.py      # JWT, password hashing
│   └── db.py            # async engine + sessionmaker
├── models/              # SQLAlchemy 2.x DeclarativeBase
├── schemas/             # Pydantic request/response models
├── services/            # business logic; no FastAPI imports
└── tests/
    ├── conftest.py      # test client + db fixtures via testcontainers
    ├── test_users.py
    └── test_auth.py
```

## Canonical patterns

### Lifespan (NOT on_startup/on_shutdown)
```python
from contextlib import asynccontextmanager
from fastapi import FastAPI

@asynccontextmanager
async def lifespan(app: FastAPI):
    # startup
    app.state.engine = create_async_engine(...)
    yield
    # shutdown
    await app.state.engine.dispose()

app = FastAPI(lifespan=lifespan)
```

### Dependency injection
```python
async def get_db(request: Request) -> AsyncSession:
    async with AsyncSession(request.app.state.engine) as session:
        yield session

@router.post("/users", response_model=UserResponse, status_code=201)
async def create_user(
    body: UserCreate,                    # Pydantic — validated at boundary
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
) -> UserResponse:
    ...
```

### Async SQLAlchemy 2.x
```python
result = await db.execute(
    select(User).where(User.email == email)
)
user = result.scalar_one_or_none()
```

## Hard rules

- Pydantic v2 (`from pydantic import BaseModel` + `model_config`, NOT `Config` class)
- Every endpoint has `response_model=`
- No `dict` request bodies — always Pydantic
- No `Session()` instantiation outside `Depends(get_db)`
- No `Query()`-style legacy SQLAlchemy
- Services NEVER import from `fastapi`; routes call services
- `BackgroundTasks(.add_task)` only for ≤ 30s + idempotent + crash-safe; otherwise Celery/RQ

## Common pitfalls

1. **Sync function with async DB** — silent deadlock or broken connection pool. Async all the way down.
2. **Sharing a session across requests** — use `Depends(get_db)` per request; never module-level session.
3. **`on_startup` / `on_shutdown`** — deprecated; use `lifespan`.
4. **Returning ORM objects directly** — Pydantic doesn't serialize; declare `response_model` + use `from_attributes=True` in model_config.
5. **`Body()` for complex bodies** — use a Pydantic class so OpenAPI is accurate.
6. **CPU-bound work in BackgroundTasks** — blocks the event loop; offload to Celery + worker.

## References

- FastAPI: https://fastapi.tiangolo.com/
- Async SQLAlchemy: https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html
- Pydantic v2 migration: https://docs.pydantic.dev/latest/migration/

## Done means

- All endpoints have typed request + response models
- Lifespan replaces on_startup/on_shutdown
- DB session via Depends, never module-level
- Routers organized by feature, mounted from main.py
