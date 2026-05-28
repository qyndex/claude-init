---
description: Plan N parallel feature streams from tasks/TASKS.md. Delegates to coordinator agent. Output: .swarms/streams/<id>/{brief.md, analysis.md, task.json} for each stream. Does NOT dispatch — use /swarm:dispatch next.
argument-hint: "[N (default: 5)] [--scope <pattern>]"
allowed-tools: Read, Glob, Grep, Edit, Write, Bash, TodoWrite
disable-model-invocation: true
---

# /swarm:plan — Plan parallel feature streams

Read the backlog, group independent tasks into N streams (default 5), write per-stream briefs.

Process:
1. Delegate to the **coordinator** agent.
2. Coordinator reads `tasks/TASKS.md` filtering for unblocked tasks (`[ ]`, no `deps:` outstanding).
3. Identifies independent groups using these rules:
   - Different `phase:` markers — usually independent
   - No overlap in `files:` listed per task — independent
   - Cap each stream at 3-5 tasks to keep stream sessions bounded
4. For each stream, writes:
   - `.swarms/streams/<id>/analysis.md` (scope + files-owned + files-shared + acceptance)
   - `.swarms/streams/<id>/brief.md` (the stream's system-prompt extension)
   - `.swarms/streams/<id>/task.json` (initial state)
5. Updates `.swarms/coordinator/decisions.log` with a "Planned N streams" entry.

Output to chat (concise):
- `N streams planned. Total tasks: M. Estimated wall-clock per stream: <range>.`
- One-line per stream: `feat-NNN: <scope summary> — <task count> tasks — owns <file count> files`
- Suggested next: `/swarm:dispatch`

$ARGUMENTS
