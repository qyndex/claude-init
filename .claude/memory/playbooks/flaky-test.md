---
name: flaky-test
description: Playbook for diagnosing and fixing a flaky test.
metadata:
  type: playbook
---

# Playbook: Flaky Test

Flaky tests are a tax on velocity. Fix or quarantine — never ignore.

## Step 1 — Confirm flakiness

```
# Run the test in isolation 20 times
for i in {1..20}; do
  <project test command> --grep '<failing test name>' && echo PASS || echo FAIL
done
```

If the test fails < 1 in 20 times, it's flaky. If it always fails, it's a regression — use `/debug` instead.

## Step 2 — Categorize

| Symptom | Likely cause |
|---|---|
| Fails only in CI, passes locally | env or timing difference |
| Fails when run after specific other tests | shared state / order dependence |
| Fails under load (parallel tests) | concurrency bug or shared resource |
| Fails intermittently with no pattern | non-determinism (clock, random, network) |
| Fails after dependency update | dependency contract changed |

## Step 3 — Isolate

- Run the test alone (`--grep` / `pytest -k` / `cargo test --test`)
- Run the test repeatedly (above loop)
- Add tracing inside the test (`console.log`/`print`) to capture state
- Check the test's dependencies (timers, network, DB)

## Step 4 — Common fixes

- **Freeze the clock**: replace `Date.now()` / `time.time()` with an injected clock.
- **Fake the network**: use `msw` (TS), `responses` (Py), `httptest` (Go).
- **Reset shared state**: use `beforeEach` / `setUp` to clean DB, cache, globals.
- **Make assertions deterministic**: sort lists before comparing, avoid `toEqual` on objects with timestamps.
- **Bound waits**: use explicit `waitFor` / `expect.poll` with a timeout, not `setTimeout(50)`.

## Step 5 — Verify the fix

Run the same 20× loop. If it now passes 20/20, the fix is real. Less than that = keep digging.

## Step 6 — Document

Add an entry to `.claude/memory/incidents/` if the cause is reusable knowledge.

## Anti-patterns

- **Retry the test on failure.** Hides the bug, doesn't fix it.
- **Mark it `skip`** without an owner and date. → Quarantined tests that nobody owns rot forever.
- **Sleep-and-pray**: `setTimeout(5000)`. Use `waitFor` with assertions.
