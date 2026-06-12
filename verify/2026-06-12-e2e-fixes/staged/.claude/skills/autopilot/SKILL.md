---
name: autopilot
description: Five-phase autonomous execution. Spec expansion → planning → execution → QA loops (max 5) → multi-perspective validation → cleanup. Aborts if same error repeats 3 times. Used by Cloud Routine overnight runs and any /loop autonomy.
when_to_use: User says "autopilot", "auto-run", "run on your own", "ultrawork", "ralph mode". Cloud Routine fires this at 11 PM. /loop wraps it.
model: sonnet
allowed-tools: Read, Glob, Grep, Edit, Write, Bash, TodoWrite, WebFetch
---

# Autopilot

Disciplined autonomous execution. Inspired by OMC's `skills/autopilot/SKILL.md`. **Five phases, hard guard rails, defined exit conditions.**

## Phase 0 — Spec expansion

- Read `tasks/TASKS.md`. Pick the next unblocked task.
- **Brownfield legacy guard (Round 14):** if `.claude/state/adopt/uncharacterized-paths.txt` exists and is non-empty, and the task's `files:` overlap any glob in it, **SKIP** the task — log `ADOPT-BLOCKED: <file> not yet characterized` to `OVERNIGHT_REPORT.md` and move on. Autonomy must not modify un-characterized legacy ("no tests = no writes"); the fix is a characterization test first (see the `characterize` skill / sprout-method), which the operator drives during `/adopt`. (`verify.sh` enforces this too — but skipping here avoids wasting a turn on work that can't pass the gate.)
- Read the parent spec + plan. Confirm `status: approved`.
- If spec has open `[OQ]` → STOP. Log to `OVERNIGHT_REPORT.md` and move to next task.
- Otherwise: expand the task into a 3-5 step micro-plan.

## Phase 1 — Planning

- Confirm the task's `accept:` command is well-formed (parses, file paths exist).
- Identify the minimal set of files to touch.
- Decide: in-session or delegate to implementer subagent? (Use dispatch-criteria skill.)
- TodoWrite the micro-plan steps.

## Phase 2 — Execution (strict TDD per `superpowers:test-driven-development`)

- For each step:
  1. **Write the failing test first.** Match the acceptance criterion from the task.
  2. **Run the test and paste the failure output** in your response. Confirm the failure message matches what you expected to see — if it doesn't, the test isn't testing the right thing.
  3. **Implement the minimum code** to make the test pass.
  4. **Run the test and paste the passing output.** No skipping this step.
  5. **Run the broader suite.** Confirm no regressions.
  6. **Refactor** if needed, keeping tests green.
- WIP-checkpoint after each step (`WIP: <decision in 6 words>`).
- If your first run of a new test passes, the test is wrong — either it was already implemented or the assertion is trivial. Investigate before proceeding.
- If any step's verification fails → enter self-heal flow.

## Phase 3 — QA loops (max 5 iterations)

- Run the task's `accept:` command.
- If exit 0 → proceed to Phase 4.
- If exit non-zero:
  - Increment QA counter.
  - If same error message appears **3 times in a row** → ABORT this task. Mark `[!]`. Move to next.
  - Otherwise: invoke `self-heal` skill (debugger → implementer fix).
  - Loop.
- Hard cap: 5 QA iterations per task. After 5, ABORT regardless.

## Phase 3.5 — PIVOT tier (deterministic, not LLM-judged)

The consecutive-abort count is **not** something you track by reading the
transcript — it is owned by `loop-iteration.sh` + `.claude/state/consecutive-aborts.json`
(the state machine from spec 001 AC-5). After each task you MUST report the outcome:

```bash
bash .claude/scripts/loop-iteration.sh record T-<id> abort      # task hit [!]
bash .claude/scripts/loop-iteration.sh record T-<id> progress   # task hit [x]
```

The loop then decides the tier deterministically:

- **1st abort** → re-attempt normally (self-heal).
- **2nd consecutive abort of the SAME task** → the loop emits `PIVOT T-<id>`. Do
  NOT retry the same approach. Delegate to the `researcher` agent using
  `.claude/templates/pivot-prompt.md`; adopt its rank-1 alternative, then re-attempt.
- **3rd consecutive abort (count ≥ 3)** → the loop exits 2 with
  `consecutive-abort cap reached` and halts. A human resets the state (or a `[x]`
  progress clears it) before the loop resumes.

This replaces any LLM-side strike-counting: the cap is enforced by the state file,
so it survives compaction, restarts, and context loss.

## Phase 4 — Multi-perspective validation

After QA passes:

- Run broader test suite (`bash .claude/scripts/verify.sh`).
- Run linter + typechecker.
- Run security scan if diff touches auth/data/network/deps.
- For UI changes: run `webapp-testing` skill, capture evidence.
- All four must pass to proceed.

## Phase 5 — Cleanup & commit

- Squash WIP commits with `bash .claude/scripts/squash-wip.sh`.
- Write the final Conventional Commits message with git trailers (per `CLAUDE.md §VI`).
- Mark task done: `bash .claude/scripts/task-status.sh T-<id> done` (lock-safe; Write/Edit on TASKS.md is constitution-guarded).
- Write a NEXUS-format handoff to `.swarms/streams/<run-id>/handoff-T-<task-id>-<ts>.yaml` (in a swarm) OR to the `OVERNIGHT_REPORT.md` "shipped" section (solo run; coordinator picks it up). Never write to `.swarms/<run-id>/` directly — that path doesn't match the coordinator's schema.
- Loop back to Phase 0 for the next unblocked task.

## Stop conditions (any one stops the run)

- No more unblocked tasks
- Wall-clock budget exceeded (default: 4 hours from start)
- Token budget exceeded
- 3 consecutive task ABORTs (enforced by the Phase 3.5 state machine — `loop-iteration.sh` exits 2 at the cap)
- Any security check fails on the diff
- User sends `/stop` or interrupts

## Output

At end of run:

- `OVERNIGHT_REPORT.md` at repo root with NEXUS format
- One PR per completed task on `claude/auto-<date>-<task>` branches
- Updated `tasks/TASKS.md`
- Memory consolidated via `/dream` (auto-runs at end if cron didn't already)

## Hard rules

- **No skipped tests.** Tier 2 self-heal first; never `// @ts-ignore`.
- **No silent error suppression.** Catch only what you understand; let the rest surface.
- **No phantom progress.** Every Phase 2/3/5 commit must include passing test evidence.
- **WIP every 5-15 minutes.** Crash recovery depends on it.
- **One task at a time per session.** Use parallel-swarm skill for cross-task parallelism.
- **Two safety layers, zero prompts.** Auto Mode is on (Sonnet 4.6 classifier reviews every tool call). PreToolUse hooks fire FIRST and hard-block destructive ops via exit code 2 regardless of mode. If the classifier denies a call you need, do NOT retry — log it and escalate.

## References

- yeachan-heo/oh-my-claudecode/skills/autopilot (source for 5-phase pattern + 3x-error abort)
- obra/superpowers (TDD + verification + self-heal patterns referenced inside)
- ChristopherKahler/paul (loop discipline)
