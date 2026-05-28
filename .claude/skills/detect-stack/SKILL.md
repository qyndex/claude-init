---
name: detect-stack
description: Detect the project's tech stack(s) — frameworks, ORMs, build tools, test runners — from lockfiles and config files. Returns a structured manifest. Used by atlas-refresh, lint dispatcher, stale-deps workflow. Round 8 C.
when_to_use: When the codebase needs structural classification — lockfile + config scan to identify languages, frameworks, ORMs, test runners; used by atlas-refresh, lint dispatcher, stale-deps.
disable-model-invocation: true
---

# Detect stack

A pure-function skill: scan the repo, return a manifest of what's present.

## Output schema

```json
{
  "languages": ["typescript", "python"],
  "frameworks": {
    "web": "Next.js 14 (App Router)",
    "api": "tRPC 11",
    "orm": "Prisma 5",
    "styles": "Tailwind CSS 3"
  },
  "build_tools": ["pnpm", "turbo"],
  "test_frameworks": ["vitest", "playwright"],
  "lockfiles": ["pnpm-lock.yaml", "package.json", "tsconfig.json"],
  "monorepo": true,
  "monorepo_tool": "turborepo",
  "primary_stack": "typescript"
}
```

## Detection rules

### Languages (from lockfiles/manifests)
| Lockfile | Language |
|---|---|
| `package.json` + (`*.ts` OR `tsconfig.json`) | TypeScript |
| `package.json` (no TS) | JavaScript |
| `pyproject.toml` / `requirements.txt` / `setup.py` | Python |
| `Cargo.toml` | Rust |
| `go.mod` | Go |
| `pom.xml` / `build.gradle(.kts)` | Java/Kotlin |
| `Gemfile` | Ruby |
| `composer.json` | PHP |
| `*.swift` | Swift |
| `*.kt` (Android) | Kotlin |
| `*.dart` (Flutter) | Dart |

### Web frameworks
| Signal | Framework |
|---|---|
| `next.config.{js,mjs,ts}` + `app/` dir | Next.js (App Router) |
| `next.config.*` + `pages/` dir | Next.js (Pages Router) |
| `remix.config.*` | Remix |
| `vite.config.*` + React | Vite-React |
| `vue.config.*` / `nuxt.config.*` | Vue / Nuxt |
| `angular.json` | Angular |
| `astro.config.*` | Astro |
| `svelte.config.*` | SvelteKit |

### API frameworks
| Signal | Framework |
|---|---|
| `@trpc/server` in deps | tRPC |
| `express` in deps | Express |
| `fastify` in deps | Fastify |
| `@nestjs/core` | NestJS |
| `hono` | Hono |
| `fastapi` in pyproject | FastAPI |
| `django` | Django |
| `flask` | Flask |
| `rails` | Rails |
| `actix-web` / `axum` / `rocket` | Rust web |
| `github.com/gin-gonic/gin` / `gofiber/fiber` | Go web |

### ORMs
| Signal | ORM |
|---|---|
| `prisma/schema.prisma` | Prisma |
| `drizzle/schema.ts` / `drizzle.config.*` | Drizzle |
| `typeorm` in deps | TypeORM |
| `sqlalchemy` | SQLAlchemy |
| `alembic.ini` | Alembic (migrations) |
| `activerecord` | ActiveRecord |
| `gorm.io/gorm` | GORM |
| `diesel.toml` | Diesel |

### Monorepo tools
| Signal | Tool |
|---|---|
| `turbo.json` | Turborepo |
| `nx.json` | Nx |
| `pnpm-workspace.yaml` | pnpm workspaces |
| `lerna.json` | Lerna |
| Workspace cargo + multiple `Cargo.toml` | Cargo workspaces |

### Test frameworks
| Signal | Framework |
|---|---|
| `vitest.config.*` / `vitest` in deps | Vitest |
| `jest.config.*` / `jest` in deps | Jest |
| `playwright.config.*` / `@playwright/test` | Playwright |
| `cypress.config.*` | Cypress |
| `pytest.ini` / `pytest` in deps | pytest |
| `*_test.go` files | go test |
| `cargo test` (always available) | cargo test |
| `rspec` in Gemfile | RSpec |

## Implementation

The detection logic lives in `.claude/scripts/atlas-refresh.sh`. This skill file documents the schema + rules. Direct script invocation: `bash .claude/scripts/atlas-refresh.sh` writes the atlas; `bash .claude/scripts/detect-stacks.sh` (Round 8 B) gives the simpler stacks-only list.

## When this skill is invoked

- Nightly via `.claude/routines/atlas-refresh.yml`
- On-demand via `/atlas refresh`
- Pre-spec via `architect.md` workflow step 1 (reads atlas)
- Pre-implement via `implementer.md` workflow step 1 (reads atlas)

## Hand-off to framework-specific skills

After detection completes, consult `.claude/skills/framework-detector/SKILL.md` which maps the detected `frameworks.{web,api}` pair to a seeded `.claude/skills/<stack>/SKILL.md` (e.g. `react-vite`, `react-node`, `flask-realtime`). The detector writes `.claude/memory/atlas/SKILL_HINTS.md` so the implementer/architect agents pick up the right skill without re-running detection.
