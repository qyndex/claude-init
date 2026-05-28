---
paths:
  - "**/*.test.*"
  - "**/*.spec.*"
  - "tests/**/*"
  - "test/**/*"
  - "__tests__/**/*"
  - "spec/**/*"
  - "e2e/**/*"
  - "cypress/**/*"
  - "playwright/**/*"
  - "**/conftest.py"
  - "**/setup-tests.*"
---

# Test rules

> Loaded when Claude is editing tests.

## TDD discipline (per superpowers:test-driven-development)

If you're writing a test for new behavior, the test must FAIL first. Run it, paste the failure output, then implement. If your first run passes, the test isn't testing what you think it is.

## Naming

- **Test name describes the behavior, not the implementation.**
  - ✅ `test_login_rejects_expired_token`
  - ❌ `test_jwt_lib_throws_TokenExpiredError`
- **One behavior per test.** A test that fails should point at exactly one cause.

## Determinism

- **No flaky tests.** A test that fails 1-in-20 must be diagnosed (see `.claude/memory/playbooks/flaky-test.md`), not retried.
- **Freeze the clock** in any test that uses time. `jest.useFakeTimers()`, `freezegun`, etc.
- **Fake the network** in unit and integration tiers. Use `msw` (TS) / `responses` (Python) / `httptest` (Go).
- **Isolate database state** — every test starts with a fresh DB or a transaction it rolls back.

## Speed

- Unit tests: < 100ms each. If slower, move to integration tier.
- Integration tests: < 5s each. Anything slower → tag and skip in default CI runs.
- E2E tests: budget total ≤ 5 min wall-clock per CI run.

## Coverage

- **Coverage is a signal, not a goal.** 100% coverage of trivial code is less valuable than 85% coverage of risky code.
- **Tier targets** (Round 8 — must match `codecov.yml` + `verify.sh`): **90% line, 85% branch** on `src/`; **95%** on critical paths (`**/auth/**`, `**/payments/**`, `**/security/**`, `**/billing/**`, `**/crypto/**`).
- **Coverage gate runs in CI** via `.claude/scripts/verify.sh` + `codecov.yml`. PRs that drop coverage > **0.5 percentage points** fail (matches `codecov.yml` threshold).
- **NOT literal 100%** — calibrated thresholds avoid test-induced design damage. See `codecov.yml` rationale.

## What to test

- **The behavior of the spec's acceptance criteria.** Every criterion maps to at least one test.
- **The error paths.** Bad input, missing fields, timeouts, network failures, concurrent access.
- **The integration boundaries.** Database calls, external API calls, message queue interactions.
- **Regressions.** Every fixed bug gets a test pinned to the issue / PR number.

## What NOT to test

- **Library internals.** Don't test that React rendering works; test that *your* component renders correctly.
- **Generated code.** Trust your generator.
- **Trivial getters/setters.** Test through the public API.
- **Implementation details.** A refactor that doesn't change behavior shouldn't break the test.

## Mocking

- **Mock at the boundary, not internals.** Mock the HTTP client, not the function that calls the HTTP client.
- **No `unittest.mock.patch` on functions you own.** Refactor instead — pass the dependency in.

## E2E specifically

- **Real seed data.** Use a fresh seeded DB or a test tenant — not internal mocks.
- **One user journey per test.** End-to-end "click here → see result there", with explicit assertions at each step.
- **Capture evidence**: screenshots, console logs, network traces. Save to `verify/<date>-<feature>/`.

## Property-based testing

- Use `fast-check` (TS), `hypothesis` (Python), `proptest` (Rust) for parsers, serializers, math-heavy code, state machines.
- Property tests find edge cases unit tests miss.
