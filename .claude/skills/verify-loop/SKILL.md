---
name: verify-loop
description: The /loop wrapper that runs autopilot until 100% verified or budget exhausted. Combines /loop, autopilot skill, verification-before-completion gate, and self-heal. Used by Cloud Routines at 11 PM and any unattended run.
when_to_use: User says "loop until done", "verify until 100%", "/verify-loop", "keep going". Cloud Routine prompt body invokes this. Autopilot wraps this.
model: opus
allowed-tools: Read, Glob, Grep, Edit, Write, Bash, TodoWrite
context: fork
agent: implementer
---

# Verify Loop

The outer loop. Runs `autopilot` skill iteratively, gated by `verification-before-completion`, with self-heal recovery. **Stops only when 100% verified or stop condition triggers.**

## The loop

```
while not stop_condition:
    1. pick next unblocked task from tasks/TASKS.md
    2. invoke autopilot skill on that task    (5-phase execution)
    3. run verification-before-completion gate
       a. if PASS  → mark task [x], commit, continue
       b. if FAIL  → invoke self-heal (3 attempts max)
          - on heal success → continue
          - on heal failure → mark task [!], log to OVERNIGHT_REPORT, continue
    4. WIP checkpoint
    5. evaluate stop conditions
end

at end:
    6. run /dream skill (consolidate memory)
    7. write OVERNIGHT_REPORT.md
    8. open PRs for completed tasks
    9. exit cleanly
```

## Stop conditions (any one stops)

- No more unblocked tasks in `tasks/TASKS.md`
- Wall-clock budget exceeded (`--until <time>` or default 4 hours)
- Token budget exceeded (`--budget <N>` or session limit)
- 3 consecutive task ESCALATIONs (self-heal exhausted on 3 different tasks in a row)
- Any security check fails on a diff (semgrep critical, gitleaks hit)
- User sends `/stop`, Ctrl+C, or any interrupt
- `tasks/TASKS.md` modified externally (file watcher detects human edit)

## Invocation patterns

### From a Cloud Routine (the headline scenario)

```
Run /verify-loop until all unblocked tasks pass verification OR 04:30 wall clock.
Use /implement, /verify, /review per task. Use playwright-skill for UI.
Use semgrep for security. WIP-checkpoint every 10 minutes.
On completion, run /dream then write OVERNIGHT_REPORT.md.
Open one PR per completed task on claude/overnight-YYYY-MM-DD-<task> branches.
```

### From /loop (in-session)

```
/loop --budget 500000 --until 02:00
```

### From the command line (headless)

```bash
claude -p --max-budget-usd 20 --max-turns 200 \
  --output-format stream-json \
  /verify-loop
```

## Verification gate (the heart)

Wraps `obra/superpowers:verification-before-completion`:

For each task, after Phase 5 of autopilot, before marking `[x]`:

1. Run task's `accept:` command → exit 0 required
2. Run `bash .claude/scripts/verify.sh` → exit 0 required (lint + typecheck + unit tests)
3. Run integration tests if defined → exit 0 required
4. For UI changes: `webapp-testing` skill → screenshots captured, no console errors, no failed network
5. For security-touched diffs: semgrep + codeql + dep audit → no high or critical findings

Only when ALL FIVE pass is the task `[x]`. Otherwise `[!]` and self-heal kicks in.

## Hard rules

- **Never skip the gate.** Even at 4:25 AM with 5 minutes left.
- **Evidence required.** A passed gate writes evidence to `verify/<date>-<task>/` — the gate itself is the proof.
- **Auto-PR per task.** One task = one PR. Don't batch.
- **Don't auto-merge.** Verify loop opens PRs; merge requires human or branch-protection automation (claude-code-action + auto-merge for green CI).
- **Self-heal max 3.** Per task. After 3, escalate and move on.

## What it produces

- N completed PRs on `claude/overnight-<date>-<task>` branches
- M handoff files in `.swarms/streams/<run-id>/handoff-*.md` (coordinator schema; the autopilot skill writes here too)
- 1 `OVERNIGHT_REPORT.md` at repo root
- 1 `/dream` consolidation pass at the end
- Updated `tasks/TASKS.md` with `[x]` and `[!]` marks

## References

- obra/superpowers/skills/verification-before-completion (gate logic)
- obra/superpowers/skills/executing-plans (loop structure)
- .claude/skills/autopilot (per-task execution)
- .claude/skills/self-heal (recovery)
- .claude/skills/handoff (NEXUS report format)
- Native /loop command: https://code.claude.com/docs/en/scheduled-tasks
