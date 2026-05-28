---
name: loop
description: Run a continuous Ralph-style autonomous loop until a budget or success condition is hit. Each iteration restarts with a fresh subagent that reads PLAN.md + progress.md from disk, picks the next unblocked task, executes, verifies, and writes back. Native to Claude Code via /loop, but this skill formalizes the discipline.
when_to_use: User wants overnight or unattended progress on a clear, machine-verifiable goal. User says "loop", "ralph", "auto run", "keep going until done", "work overnight".
argument-hint: "[--budget tokens] [--until time] [--max-iter N]"
model: sonnet
allowed-tools: Read, Glob, Grep, Edit, Write, Bash, TodoWrite
context: fork
agent: implementer
---

# Loop

A bounded, resumable, evidence-driven autonomous loop. Modeled on Geoffrey Huntley's Ralph + Anthropic's `/loop` command.

## When to use

Use a loop only when **all** of these are true:

- The goal is machine-verifiable (tests pass / lint clean / endpoint returns 200).
- The work is decomposed into tasks in `tasks/TASKS.md`.
- A wrong direction does not compound silently (e.g., wholesale design rewrite is NOT loop material).
- You can budget tokens and time honestly.

## When NOT to use

- Ambiguous design work
- New-area scaffolding without a spec
- Anything that touches production data
- Anything without a `verifyCompletion()` you can encode

## Process

```
1. Confirm prerequisites:
   - tasks/TASKS.md exists and has pending unblocked tasks
   - .claude/scripts/verify.sh exists and exits 0 when project is healthy
   - Running inside a worktree (not main)

2. Declare the budget:
   --budget 500000          (token cap; abort when crossed)
   --until 02:00            (wall-clock cap)
   --max-iter 20            (iteration cap)

3. Loop:
   while not stop_condition:
     a. Pick next unblocked task (tasks/TASKS.md).
     b. Delegate to implementer subagent (fresh context).
     c. On subagent return:
        - if completed:
            stage commit, mark [x], capture token usage
        - if failed:
            log failure to progress.md, increment failure counter,
            move on to next task (don't retry the same one)
     d. Run .claude/scripts/verify.sh
     e. Write summary line to plans/active/<id>-progress.md
     f. Evaluate stop conditions

4. On stop, report:
   - tasks completed
   - tasks failed
   - tokens spent
   - wall time
   - next manual step
```

## Stop conditions (any one triggers stop)

- Budget reached (`--budget`, `--until`, `--max-iter`)
- Two consecutive iterations produced no committable diff
- Verify script returns non-zero **for the second time in a row**
- Any security check fails
- User interrupts (`^C` or `/stop`)

## Hard rules

- **Always in a worktree.** Never run a loop on main.
- **Always verifiable.** No verify command → no loop.
- **Always budgeted.** No budget → no loop.
- **Resumable.** Every iteration writes a progress.md so a fresh session can pick up.
- **Audited.** Every iteration's tokens, time, and diff size are logged.

## Output

```
plans/active/<id>-progress.md   (appended each iteration)
.claude/memory/playbooks/loop-<date>.md   (post-mortem)
```

After stop: "Loop stopped after <N> iterations. <M> tasks completed. <K> failed. Tokens: <T>. Time: <W>. Next: <manual step>."
