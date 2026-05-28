# Tasks

Append-only task ledger. The planner agent (`.claude/agents/core/planner.md`) populates this from approved plans.

## Format

```
- [ ] T-NNN  | spec:NNN  | phase:N  | priority: <P>  | created: <ISO>  | last_touched: <ISO>  | deps: T-AAA, T-BBB  | parallel: yes|no  | est: <Nm>
  summary: <verb-first one-line description>
  files: path/to/file1, path/to/file2
  accept: <shell command that exits 0 when this task is done>
  owner: @<person-or-implementer>
```

### Field reference

| Field | Required | Notes |
|---|---|---|
| `T-NNN` | yes | monotonic ID across the whole repo |
| `spec:NNN` | yes | spec the task implements |
| `phase:N` | yes | phase within the plan (matches plan.md) |
| `priority` | yes | see priority taxonomy below — drives `/triage` ordering |
| `created` | yes | ISO timestamp; required for `[!]`/`[s]` aging via `/debt age` |
| `last_touched` | optional | ISO timestamp; updated when status changes or block reason is updated |
| `deps` | optional | comma-separated task IDs |
| `parallel` | optional | `yes` if it can run beside its siblings |
| `est` | yes | honest minutes estimate; if >5min, decompose |
| `owner` | yes | `@<person>` for human-only tasks, `implementer` for agent tasks |

### Priority taxonomy (drives `/triage` ordering)

| Priority | Source | SLA |
|---|---|---|
| `hotfix` | **live prod alert (Sentry/SLO burn/synthetic) — externally originated** | **NOW — top of queue, pre-empts everything** |
| `incident-followup` | postmortem action item | this sprint |
| `security` | security review or `security` agent flagged | this sprint |
| `P1-spec` | spec marked `priority:P1` | this sprint |
| `debt` | aged `[!]` items + tech debt | next sprint |
| `normal` | most planner tasks | when bandwidth |
| `cleanup` | flag cleanup, dep upgrades | when bandwidth |
| `deprecation` | sunset / migration | quarter-bounded |

**Hotfix tasks** (Round 12) carry extra fields: `fingerprint:` (Sentry dedup key), `sentry:` (permalink), `hotfix_issue:` (projected issue #). Inserted at the TOP of `## Active` by `hotfix-to-task.sh`. `spec:HOTFIX` is a sentinel — a hotfix has no originating spec.

## Status legend

- `[ ]` pending — eligible for `/implement next`
- `[~]` in_progress — currently being worked
- `[x]` completed — `accept:` exited 0 AND verification passed
- `[!]` failed — `accept:` did not pass; debt register entry. **Requires `reason:` line.**
- `[s]` skipped — explicitly deferred. **Requires `reason:` line.** Visible in `/debt list`.
- `[b]` blocked — waiting on a dep/decision/external. **Requires `blocked_by:` line.**

## Conventions

- Task IDs are monotonic across the whole repo (don't reset per spec/plan).
- Every task has an `accept:` command. No exceptions.
- Dependencies are explicit. The implementer follows the DAG.
- `parallel: yes` means the task can run alongside its siblings without conflict.
- Estimate `est:` honestly. If > 5 minutes, decompose.
- **Every status change updates `last_touched:`.** This is how staleness is computed.
- **`[!]` and `[s]` without `created:`** are invisible to aging — the SLA can't trigger. Treat as a format violation.

## Hygiene cadence

| Command | When | Purpose |
|---|---|---|
| `/triage` | weekly (Monday) | re-rank backlog |
| `/debt list` | weekly | see all `[!]`/`[s]` |
| `/debt age` | monthly | surface SLA breaches |
| `/debt triage` | monthly | force decision on >90d items |
| `/owner-walk @<departed>` | on departure | re-assign all artifacts |

---

## Active

_(no tasks yet — populated by `/tasks <plan-id>`)_

## Archive

Move completed batches here when the plan ships. Keep the file < 2000 lines. When this file exceeds 2000 lines, move ARCHIVE section to `tasks/archive/TASKS-<YYYY-Q>.md` (see `.claude/routines/quarterly-archive.yml`).
