---
name: verify
description: Run the actual application end-to-end and exercise the user journey from the spec. Phase 6 of the eight-phase workflow. Delegate to verifier agent. Captures screenshots, logs, HTTP traces. The "did it actually work?" gate.
when_to_use: Implementation is complete (all tasks [x]) and you need to confirm the user journey works in a running system. User says "verify", "run it", "does it work", "test end-to-end".
argument-hint: "<feature id or 'latest'>"
model: sonnet
allowed-tools: Read, Glob, Grep, Bash, WebFetch
context: fork
agent: verifier
mcpServers: [chrome-devtools, playwright]
---

# Verify

Run the app. Exercise the user journey. Capture evidence. Mark PASS or FAIL.

## Process

1. Read the spec's user journey.
2. Boot the app (`bash .claude/scripts/run.sh` or project-specific).
3. Walk the journey step by step, capturing evidence at each step.
4. Walk the negative paths (bad input, missing auth, etc.).
5. Save artifacts under `verify/<date>-<feature>/`.
6. Write the report.

## Evidence types

- Screenshots (browser MCP `take_screenshot`)
- DOM/a11y snapshots (`take_snapshot`)
- HTTP responses (`curl -i` or Postman collection)
- Log excerpts (`docker compose logs --since 5m`)
- Console messages (`list_console_messages`)
- Network requests (`list_network_requests`)
- Exit codes (for CLIs)

## Hard rules

- **Evidence before assertion.** "Looks fine" is not verification.
- **The user journey, not just tests.** Unit tests passing ≠ user works.
- **Negative paths too.** Try the obvious failure.
- **Real-ish data.** Fresh seeded DB or test tenant; no internal mocks.
- **Capture, don't summarize.** Save raw artifacts so future you can re-examine.

## Output

```
verify/<date>-<feature>/REPORT.md
verify/<date>-<feature>/*.png
verify/<date>-<feature>/*.json
verify/<date>-<feature>/*.log
```

REPORT.md format: see `.claude/agents/quality/verifier.md`.

After save: "Verification PASS — N steps, M negative paths. Ready for /review." OR "Verification FAIL at step K. See verify/<date>/REPORT.md. Hand back to implementer."
