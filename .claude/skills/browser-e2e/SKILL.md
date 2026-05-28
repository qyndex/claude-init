---
name: browser-e2e
description: Browser-driven E2E discipline. Thin pointer — defers to anthropics:webapp-testing plugin for Python Playwright scripts and to playwright MCP / chrome-devtools MCP / Claude in Chrome based on the situation. Use when verifying any web change.
when_to_use: Verifying a web app, debugging a UI bug, generating E2E tests from a spec, capturing visual evidence. User says "test in browser", "E2E", "open the app and try", "did the UI work".
mcpServers: [chrome-devtools, playwright]
model: inherit
---

# Browser-Driven E2E

Decide which tool **before** writing code:

| Goal | Tool | Why |
|---|---|---|
| Authenticated user journey (Gmail, your admin panel, Notion) | **Claude in Chrome** (`claude --chrome`) | Uses your real cookies |
| Deterministic CI test, no auth | **`anthropic:webapp-testing` plugin** | Python Playwright + `with_server.py` lifecycle helper |
| Exploratory drive (clicks, fills, snapshots) | **playwright-mcp** | Snapshot-based deterministic refs |
| Perf, network, Lighthouse | **chrome-devtools-mcp** | Full DevTools, traces |
| Visual regression | **Chromatic / Percy / Argos** (out of band, CI) | Pixel diff at PR time |

## The user-journey pattern (playwright-mcp)

```
1. browser_navigate(url)
2. browser_snapshot()                    # capture a11y tree
3. browser_click(ref: "<from snapshot>")
4. browser_fill(ref: "...", value: "...")
5. browser_wait_for(text: "Welcome")
6. browser_take_screenshot(filename: "verify/<date>/step-<n>.png")
7. browser_console_messages()    # assert: no errors
8. browser_network_requests()    # assert: 200 on critical endpoints
```

## The codegen-then-expand pattern

```bash
npx playwright codegen http://localhost:3000
# perform the journey by hand
# save as tests/e2e/<feature>.spec.ts
# feed to researcher agent: "expand with edge cases per the spec acceptance criteria"
```

## Hard rules

- **Real-ish data.** Fresh seeded DB or test tenant. No internal mocks.
- **Capture at every step.** Screenshot before and after the critical action.
- **Assert on the journey, not implementation.** "User sees dashboard" > "div.welcome present".
- **Negative paths.** Bad password, missing field, expired session. Each gets a step.
- **Save artifacts.** `verify/<date>-<feature>/` is the home.

## Coverage gate ("100% coverage" enforcement)

Per CLAUDE.md §VII, the verifier captures coverage alongside screenshots. `.claude/scripts/verify.sh` enforces:

| Tier | Threshold | Source |
|---|---|---|
| Line coverage | ≥ 80% on changed files | `c8` (Node), `coverage.py` (Python), `go test -cover` |
| Branch coverage | ≥ 70% on changed files | `c8`, `coverage.py` |
| E2E user journey | 100% of spec acceptance criteria | one Playwright step per criterion |

Configure your test runner to emit `coverage/coverage-summary.json` (c8 / `@vitest/coverage-v8` / `coverage report --format=json`). The gate reads that file and fails on threshold breach.

For UI-specific coverage:
- **Playwright + c8**: `c8 --reporter=json-summary playwright test` produces the summary `verify.sh` reads.
- **@playwright/test built-in**: enable trace in `playwright.config.ts`, post-process for code coverage.

If a project has no coverage tooling yet, **the autopilot verifier must skip the gate and flag ESCALATION** in `OVERNIGHT_REPORT.md`. Never fake-pass without the report. Set `SKIP_COVERAGE=1` for explicit short-term skips.

## References

- chrome-devtools-mcp: https://github.com/ChromeDevTools/chrome-devtools-mcp
- playwright-mcp: https://github.com/microsoft/playwright-mcp
- anthropic:webapp-testing: https://github.com/anthropics/skills/blob/main/skills/webapp-testing/SKILL.md
- Claude in Chrome: https://code.claude.com/docs/en/chrome
