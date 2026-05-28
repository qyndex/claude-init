---
description: Generate a handoff document so a fresh Claude Code session can pick up where you left off. Captures current state, in-flight work, open questions, next steps. Modeled on qdhenry/Claude-Command-Suite session/handoff-continue.
argument-hint: "[notes for the next session, optional]"
allowed-tools: Bash, Read, Glob, Grep, Write, TodoWrite
disable-model-invocation: true
---

# /handoff — Context handoff for the next session

Write a self-contained brief so a fresh session can resume in one read. Saves to `.claude/memory/playbooks/handoff-<date>.md` and (if `$ARGUMENTS` are given) prepends them as context.

## Process

1. Run `/status` style probes (branch, dirty, active spec/plan, pending tasks, recent commits).
2. Pull any in-progress task notes from `tasks/TASKS.md`.
3. List unresolved `[OQ]` items from the active spec.
4. List the next 3 unblocked tasks.
5. Write the handoff to `.claude/memory/playbooks/handoff-<YYYYMMDD-HHMM>.md`.

## Output format

```
# Handoff — <YYYY-MM-DD HH:MM>

## State
- Branch: <branch> (dirty: <N> files)
- Last commit: <sha> <subject>
- Active spec: specs/active/<id>-<slug>.md  (status: <draft|review|approved>)
- Active plan: plans/active/<id>-<slug>.md  (status: <draft|review|approved>)

## In flight
<bullet list of tasks currently in_progress, with paths and current state>

## Open questions
<unresolved [OQ] items from spec(s)>

## Next 3 tasks
1. T-<id> — <verb-first summary>  (deps: T-<id>)
2. T-<id> — <verb-first summary>
3. T-<id> — <verb-first summary>

## Notes from previous session
$ARGUMENTS

## Resume command
> /status
> (then `/implement next` if a task is unblocked)
```

After writing, echo a one-line: "Handoff at .claude/memory/playbooks/handoff-<date>.md — read this first in the next session."
