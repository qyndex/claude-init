---
name: tdd-loop
description: The strict red→green→refactor loop, mechanically enforced. Write a failing test FIRST (red), capture the failure as a durable artifact, implement minimally (green), capture the pass, then refactor. Round 10 A — the skill 5 files referenced that did not exist.
when_to_use: Implementer agent executing any task; user says "TDD", "test first", "red green refactor"; any source code change that implements a spec acceptance criterion.
model: inherit
disable-model-invocation: false
---

# TDD Loop — red → green → refactor, enforced

## Mandate

No production code without a failing test that demanded it. The transition from red to green is captured as a **durable artifact** (`verify/<date>/<task>/red.log` + `green.log`), not just pasted in the transcript — so the factory can PROVE the test went red before it went green.

## The loop

### 1. RED — write the failing test first

- Write the test that encodes the spec's acceptance criterion. **Tag it with the AC id** (`@AC-01` / `{ tag: ['@AC-01'] }` / docstring `AC-01`).
- Run the task's `accept:` command (or the specific test).
- **Capture the failure**: `bash .claude/scripts/tdd-ledger.sh red <task-id> "<accept-command>"` → writes `verify/<date>/<task-id>/red.log` with the command + exit code (MUST be non-zero) + output excerpt.
- If the test passes on first run, the test is wrong (asserts nothing, or the behavior already exists). Fix the test until it fails for the RIGHT reason.

### 2. GREEN — implement minimally

- Write the **minimum** code to make the test pass. No speculative features (CLAUDE.md §I.2 Simplicity First).
- Run the same command.
- **Capture the pass**: `bash .claude/scripts/tdd-ledger.sh green <task-id> "<accept-command>"` → writes `verify/<date>/<task-id>/green.log` (exit code MUST be 0).

### 3. REFACTOR — clean up, stay green

- Improve names, remove duplication, extract helpers.
- Re-run; confirm still green (the green.log timestamp updates).
- Never add behavior here — that needs a new red test.

## Enforcement (what makes this real, not honor-system)

| Mechanism | What it catches |
|---|---|
| `tdd-ledger.sh` writes red.log + green.log | Proof the test went red before green; both committed under `verify/` |
| `verify.sh` requires both logs for any `[x]` task | A task marked done without a red→green transition fails the gate |
| `assert-density.sh` (verify.sh + CI) | Assertion-free tests (`expect(true).toBe(true)`) |
| `validate.sh` accept-is-a-test gate | `accept: echo done` — accept must invoke a test runner |
| `story-test-map.sh` (wired into verify.sh) | User story without an E2E test |
| `mutation.yml` on critical paths | Tests that pass but don't actually constrain behavior |

## Hard rules

- **Red before green, always.** The ledger proves it. Skipping red = the task fails verify.
- **One test, one behavior.** Don't batch 5 behaviors into one test.
- **AC-tagged.** Every test that proves an acceptance criterion carries its AC id.
- **Assertions required.** A test with no `expect`/`assert` is not a test.
- **Minimal green.** Don't implement beyond what the red test demands.
- **Refactor stays green.** New behavior in refactor → stop, write a new red test.

## The honest ceiling

Tooling proves a test ran red-then-green, contains assertions, and kills mutants. It does NOT prove the test asserts the RIGHT behavior — that the test maps to spec intent rather than to the implementation. That judgment stays with the agent's discipline (this skill) + the reviewer agent reading the diff against the spec. Tooling raises the floor; the reviewer certifies the ceiling.

## References

- obra/superpowers: `test-driven-development` skill (the discipline)
- Kent Beck, TDD By Example (red/green/refactor origin)
- Ledger: `.claude/scripts/tdd-ledger.sh`
- Gate: `.claude/scripts/verify.sh` + `assert-density.sh`

## Done means

- `verify/<date>/<task-id>/red.log` exists (exit ≠ 0)
- `verify/<date>/<task-id>/green.log` exists (exit = 0)
- Test is AC-tagged and contains ≥1 real assertion
- Code is minimal for the test
- Refactor left it green
