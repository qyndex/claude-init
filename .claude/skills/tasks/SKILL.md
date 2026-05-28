---
name: tasks
description: Decompose an approved plan into 2-5 minute atomic tasks with machine-verifiable acceptance commands. Phase 4 of the eight-phase workflow. Delegate to planner agent. Modeled on github/spec-kit /speckit.tasks.
when_to_use: A plan is approved and you need a work breakdown. User says "break it into tasks", "what's the task list", "decompose the plan".
argument-hint: "<plan id>"
model: sonnet
allowed-tools: Read, Write, Edit, Glob, Grep, TodoWrite
---

# Tasks

Convert an approved plan into the task DAG that the implementer will execute one at a time.

## Process

1. **Read the plan** (`plans/active/<id>-<slug>.md`). Confirm `status: approved`.
2. **Delegate to the planner** agent.
3. **Validate** — every plan phase exit criterion must be covered by the union of task acceptance commands.
4. **Append to `tasks/TASKS.md`** using the canonical task format.
5. **Mirror in TodoWrite** for in-session tracking.

## Task format

```
- [ ] T-042  | spec:001  | phase:1  | deps: T-041  | parallel: yes  | est: 3m
  summary: <verb-first one-line description>
  files: path/to/file1.ts, path/to/file2.test.ts
  accept: pnpm test src/auth/login.test.ts -q
  owner: implementer
```

Fields:
- `T-NNN` — unique id, monotonic across the repo
- `spec:` — parent spec id
- `phase:` — plan phase number
- `deps:` — task ids this depends on (must complete first)
- `parallel:` — `yes` if can run in parallel with sibling tasks
- `est:` — agent time estimate; aim ≤ 5m
- `accept:` — shell command that returns 0 when the task is done

## Hard rules

- **2-5 minutes per task.** Larger = decompose. Smaller = combine.
- **Machine-verifiable.** No task without an `accept:` command.
- **Explicit dependencies.** If a task needs another's output, list it in `deps:`.
- **Mark `[P]`.** Parallel-safe tasks must be flagged so swarms can fan out.
- **Cover the plan.** Sum of `accept:` results must imply plan phase complete.

## Output

```
tasks/TASKS.md  (append)
```

After save: "Decomposed plan <id> into <N> tasks across <M> phases. Parallel-safe: <K>. Critical path: T-a → T-b → T-c. Ready for /implement."
