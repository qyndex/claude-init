# Project Memory Index

This index is auto-loaded into every Claude Code session. Keep entries short (one line each, < 150 chars). The deeper content lives in the linked files.

## Memory taxonomy

- **decisions/** — ADR-style architectural decisions (one file per decision)
- **patterns/** — reusable code patterns specific to this codebase
- **anti-patterns/** — what didn't work and why (Round 7 D — populated by /abandon)
- **incidents/** — postmortems and "what not to do again" (production failures)
- **post-mortems/** — abandoned initiatives, killed bets (Round 7 D — distinct from incidents)
- **playbooks/** — repeatable operational procedures
- **deprecations/** — registry of sunset features/APIs
- **feedback/** — customer signal registry (Round 7 C)

Add a one-line entry below each time you write a new memory file.

---

## Decisions

<!-- Format: - [Title](decisions/file.md) — one-line hook -->

_(none yet)_

## Patterns

<!-- Format: - [Title](patterns/file.md) — one-line hook -->

_(none yet)_

## Incidents

<!-- Format: - [Title](incidents/file.md) — one-line hook -->

- [Constitution unprotected from agent writes (SEV1)](incidents/2026-05-28-sec-constitution-unprotected.md) — five-agent audit found CLAUDE.md §VII/§X security claims were documentation theater; fix tracked in specs/active/001-harness-hardening.md

## Playbooks

- [Setting up a new feature](playbooks/new-feature.md) — the full /constitution → /specify → /ship flow
- [Debugging a flaky test](playbooks/flaky-test.md) — systematic isolation pattern
- [Rolling back a bad release](playbooks/rollback.md) — git revert + migration revert + deploy
- [cross/domain-events](patterns/cross/domain-events.md) — Aggregates publish events; subscribers in separate module
- [cross/repository-pattern](patterns/cross/repository-pattern.md) — DB access behind an interface; business logic depends on the interface
- [cross/result-type](patterns/cross/result-type.md) — Use Result<T,E> for expected failures; exceptions for unexpected
- [fastapi/lifespan-context-manager](patterns/fastapi/lifespan-context-manager.md) — Use @asynccontextmanager lifespan; never on_startup/on_shutdown
- [flask/application-factory](patterns/flask/application-factory.md) — create_app() returns Flask instance; no module-level app
- [nextjs/server-vs-client-components](patterns/nextjs/server-vs-client-components.md) — Default to RSC; mark 'use client' only at leaf interactivity
- [node-api/layered-architecture](patterns/node-api/layered-architecture.md) — router → controller → service → repository; controllers never touch DB
- [react-vite/lazy-suspense-route-split](patterns/react-vite/lazy-suspense-route-split.md) — Split routes via React.lazy + Suspense; never at leaves
