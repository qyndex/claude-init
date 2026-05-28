---
name: implement
description: Execute tasks from tasks/TASKS.md one at a time using strict TDD. Phase 5 of the eight-phase workflow. Delegate each task to the implementer agent. Walks the DAG, respects deps, fans out [P] tasks if requested.
when_to_use: Spec, plan, and tasks all approved and consistent. User says "implement", "build it", "let's code", "start coding", or runs `/implement <task-id>`.
argument-hint: "<task id, 'next', or 'all'>"
model: opus
allowed-tools: Read, Glob, Grep, Edit, Write, Bash, TodoWrite
context: fork
agent: implementer
---

# Implement

Walk the task DAG and execute each task with strict TDD discipline.

## Process

```
1. Read tasks/TASKS.md.
2. If arg is a task id, work on that task only.
   If arg is "next", pick the next unblocked task (deps satisfied, status pending).
   If arg is "all", loop until no unblocked tasks remain or a task fails.
3. For each task:
   a. Mark in_progress in TodoWrite.
   b. Delegate to the implementer agent (which uses the tdd-loop skill).
   c. On agent return, mark completed and refresh the DAG.
4. If a task fails, stop the loop, report, and hand back to the user.
```

## Hard rules

- **One task at a time per agent.** Don't pile tasks into one invocation.
- **Strict TDD inside each task.** The implementer agent uses `.claude/skills/tdd-loop/SKILL.md` non-negotiably.
- **Respect deps.** Never start a task whose deps are not `[x]`.
- **Fan out only for `[P]` tasks.** And only if the user opted in.
- **Stop on failure.** Cascading failures are worse than a clean halt.

## Per-task workflow (handled by implementer agent)

1. Read parent spec, plan, task.
2. Write failing test.
3. Watch it fail (paste output).
4. Implement minimum code.
5. Watch it pass (paste output).
6. Run broader test suite.
7. Lint + format.
8. Commit (Conventional Commits).
9. Update tasks/TASKS.md + TodoWrite.

## Output

```
Each completed task → 1 commit in git history.
tasks/TASKS.md → [x] mark, completed-at timestamp.
TodoWrite → completed.
```

After loop ends: "Implementation complete. <N> tasks done, <M> commits. Ready for /verify."
