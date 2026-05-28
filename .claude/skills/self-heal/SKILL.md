---
name: self-heal
description: When a test fails, lint errors, or CI breaks — diagnose with debugger agent, propose minimal fix, implementer applies, verifier reruns, loop up to 3 attempts then escalate. Combines Anthropic Auto-Fix + Playwright self-heal + 4-tier escalation pattern.
when_to_use: Auto-triggered by stop-verify hook when verify.sh exits non-zero. User says "fix this", "make it pass", "auto-heal", "the tests are red". Used inside /loop iteration.
model: inherit
---

# Self-Heal

A failure is not "done." It's a debugging task with a defined recovery path.

## The four tiers (escalate only when the prior tier fails)

```
Tier 1 — Pre-flight retry         (transient: network, flake, race)
        ↓
Tier 2 — Debugger diagnosis       (root cause via 4-phase loop)
        ↓
Tier 3 — Implementer applies      (minimal fix from diagnosis)
        ↓
Tier 4 — Human escalation         (after 3 failed Tier 1-3 cycles)
```

## Process

### Tier 1 — Transient retry (max 1)
- If the error message matches transient patterns (timeout, connection reset, "Test timeout after Nms" on first run), rerun once.
- If second run succeeds, log to `.claude/memory/incidents/flaky-<date>.md` and move on.
- If second run fails, escalate to Tier 2.

### Tier 2 — Debugger diagnosis (1 invocation)
- Delegate to `debugger` agent with the failure output.
- Debugger runs reproduce → isolate → diagnose → fix-proposal (4 phases).
- Output: `file:line` + cause + minimal fix proposal.
- **No commits** by debugger.

### Tier 3 — Implementer applies (1 invocation)
- Delegate to `implementer` agent with the debugger's fix proposal.
- Implementer writes a failing test first (capturing the bug), then the fix, then watches green.
- Run the broader test suite to confirm no regression.
- Commit with `fix(<scope>): <summary>` + git trailer `Confidence: high` if all tests green; `Confidence: medium` if only the targeted test passes.

### Tier 4 — Human escalation (after 3 cycles fail)
- Stop the loop.
- Write `OVERNIGHT_REPORT.md` or PR comment with:
  - Failure output
  - Debugger's three diagnoses
  - Implementer's three attempts (commits)
  - Why each failed (paste verify output)
  - Suggested human next step
- Mark the task `[!]` in `tasks/TASKS.md`.

## Hard rules

- **Don't fix without understanding.** Tier 2 is mandatory before any code change.
- **Don't suppress symptoms.** No `try/except: pass`, no `// @ts-ignore`, no broad `catch {}`. If the fix looks like suppression, escalate.
- **One fix per attempt.** Don't batch hypotheses. Test each independently.
- **Escalate at 3 attempts, not 5.** A bug that resists 3 root-cause-driven fixes is a human problem.
- **Document.** Every escalation writes to `.claude/memory/incidents/`.

## Auto-trigger

The `stop-verify.sh` hook fires this skill when:
- Any task's `accept:` command exits non-zero
- `bash .claude/scripts/verify.sh` exits non-zero
- `/loop` iteration reports failure

## References

- PolarOrchid/ClaudeWatch (4-tier recovery pattern)
- obra/superpowers/skills/systematic-debugging (4-phase debugger loop)
- Anthropic Auto-Fix (CI-side self-healing via claude-code-action)
