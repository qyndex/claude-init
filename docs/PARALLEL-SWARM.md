# Parallel Feature Swarm

> 5-10 features built in parallel via native Claude Code background sessions and worktrees. Coordinator orchestrates; you sit back.

## Mental model

```
You (coordinator session, foreground)
  └── /swarm:plan 5
       └── coordinator agent reads tasks/TASKS.md, writes 5 stream briefs

  └── /swarm:dispatch
       ├── claude --bg -w feat-001 --agent feature-stream → daemon process 1
       ├── claude --bg -w feat-002 --agent feature-stream → daemon process 2
       ├── claude --bg -w feat-003 --agent feature-stream → daemon process 3
       ├── claude --bg -w feat-004 --agent feature-stream → daemon process 4
       └── claude --bg -w feat-005 --agent feature-stream → daemon process 5

  └── /swarm:status   (watch the fleet)
  └── /swarm:merge    (PR + CI + merge for each PASS)
```

## Native primitives doing the heavy lifting

| Capability | Provided by | We provide |
|---|---|---|
| Background daemon | `claude --bg` (Claude Code v2.1.144+) | Stream brief content |
| Worktree per stream | `claude -w <name>` | Stream scope analysis |
| Fleet monitoring | `claude agents --json` | `/swarm:status` formatting |
| Resume on crash | `claude respawn <id>` | `/swarm:respawn` wrapper |
| Per-session model/budget | `--model`, `--max-budget-usd`, `--max-turns` | Sensible defaults ($5, 200 turns) |
| Agent teams (optional) | `--teammate-mode` + experimental flag | feature-stream + reviewer pattern |
| Resume from PR branch | `claude --from-pr <N>` | Useful for human-handoff |

## When to use the swarm

**Good fits:**
- Backlog of 10+ independent features
- A "v2 launch" with parallel modules
- Refactor cluster (5+ files needing similar treatment)
- Stack-wide config changes (CI, deps, lint rules)
- End-of-sprint cleanup
- Documentation sweep

**Bad fits:**
- One complex feature (use a single `--bg` session instead)
- Cross-cutting refactor where everything touches everything (sequential is safer)
- Greenfield project with no scaffold yet (build the scaffold first, sequentially)
- Features blocked on each other (use coordinator-led sequential execution)

## File ownership rules

The CCPM rule: **one designated owner per shared file.** Multiple streams may *read* a shared file; only the owner writes.

Example:

| File | Owner stream | Why |
|---|---|---|
| `package.json` | feat-001 | first to add deps; others rebase after |
| `src/types/api.ts` | feat-002 | API stream owns the contracts |
| `tests/setup.ts` | feat-003 | test stream owns shared fixtures |
| `src/auth/*` | feat-001 | exclusive — no other stream touches |

Coordinator enforces this by writing it into each stream's `analysis.md`. Streams check before writing.

## State files

```
.swarms/
├── coordinator/
│   ├── fleet.json       # {streamId: {sessionId, status, worktree, branch, spawned}}
│   └── decisions.log    # append-only timeline
├── streams/
│   └── feat-001/
│       ├── brief.md     # system-prompt extension (loaded via --append-system-prompt-file)
│       ├── analysis.md  # coordinator's scope decomposition
│       ├── task.json    # ccg-workflow schema; updated by stream
│       └── handoff-*.md # NEXUS handoffs from the stream
└── templates/
    ├── brief.md
    ├── analysis.md
    └── task.json
```

Coordinator owns `coordinator/` and templates. Each stream owns its own `streams/feat-NNN/` directory.

## Typical session

```
# Morning, you sit down with 12 tasks in tasks/TASKS.md
$ claude

> /swarm:plan 5
  Coordinator plans 5 streams covering 11 of the 12 tasks (1 stays in backlog due to cross-deps).

> /swarm:dispatch
  Spawns 5 background sessions. Each gets its own worktree.

> /swarm:status
  Shows running streams. Two have already written handoffs.

# Go to lunch.

> /swarm:status
  feat-001 → QA-PASS (3 tasks done)
  feat-002 → running (2 of 3 tasks done)
  feat-003 → QA-FAIL (self-heal in progress, attempt 2 of 3)
  feat-004 → QA-PASS (2 tasks done)
  feat-005 → ESCALATION (test fixture corrupted; human help needed)

> /swarm:merge
  Opens PR #420 for feat-001, PR #421 for feat-004. Waits for CI. Merges both.
  Files an issue for feat-005.

> /swarm:status
  feat-002 → running
  feat-003 → QA-PASS (self-heal succeeded on attempt 3)
  All others: merged or escalated

> /swarm:merge
  Opens PR #422 for feat-003. Merges after CI.

# By end of day: 4 features shipped, 1 escalated (now a tracked issue), 1 still running.
```

## Native CLI cheat sheet

```bash
# Spawn a background session manually
claude --bg -n my-feature -w my-feature --agent feature-stream

# List all sessions (foreground + background)
claude agents
claude agents --json

# Attach interactively to a background session
claude attach <id-or-name>

# Tail its logs without attaching
claude logs <id-or-name>
claude logs <id-or-name> --follow

# Stop cleanly
claude stop <id-or-name>

# Restart a crashed session
claude respawn <id-or-name>

# Remove from session list
claude rm <id-or-name>

# Daemon health
claude daemon status
```

## Cost & budgets

A typical swarm of 5 streams running for ~2 hours each:
- Per stream: 200K-400K tokens (~$3-5 USD)
- Total: ~$15-25 USD for the swarm
- Wall clock: 2-3 hours (parallel) vs 10-15 hours (sequential)

Hard cap: `--max-budget-usd 5` per stream, total ~$30 even if all 6 streams hit their caps.

## Verified merge (Round 6 E)

`/swarm:merge` runs `.claude/scripts/verified-merge.sh <stream>` for each stream
with `status: qa_pass` in its NEXUS YAML handoff. The protocol catches **semantic**
conflicts that flat squash-merge would ship as broken:

1. **Rebase onto verified siblings.** Already-merged streams' branches are rebased
   into this stream before integration test. A stream that depends on a sibling's
   renamed symbol catches the missing symbol *now*, not at runtime.
2. **Integration test on the rebased state.** Runs `verify.sh` + `local-pr-check
   --heavy` + `contract-tests.sh <stream>`. The contract-test checks that every
   `exported_symbol` / `http_route` / `db_column` / `flag` declared in the stream's
   `analysis.md` under `## Contracts consumed` is actually present on the integrated
   branch.
3. **AI-mediated semantic conflict resolution.** If integration fails, spawn a
   debugger session (max 30 turns, $2 budget) to propose minimal reconciliation.
   Re-runs verify after the fix. **AI mediation rate is expected at ~10–12% of merges.**
4. **Merge.** Only proceeds if step 2 (and 3, if invoked) pass.
5. **Post-merge verify.** Re-runs `verify.sh` on main. **Auto-reverts** + spawns
   an auto-fix PR session on failure.

Declared contracts live in `analysis.md` (template at `.swarms/templates/analysis.md`):

```
## Contracts consumed
- exported_symbol:ts:src/services/user.ts:fetchUser
- http_route:POST:/api/users
- db_column:users:email_verified
- flag:checkout_v2
```

## Gotchas

| Gotcha | Symptom | Fix |
|---|---|---|
| Stream renames a function another stream calls | semantic conflict; both pass per-stream CI | **verified-merge.sh catches via rebase-onto-sibling + contract-tests** |
| Two migrations same date | duplicate timestamp on main | declare via `db_column:` in analysis.md; verified-merge runs migrations during integration test |
| Shared types drift | runtime "field X required" after merge | `exported_symbol:` contract checks shape |
| Stream consumes a flag that doesn't exist yet | undefined dereference | `flag:` contract |
| Two streams collide on a file | textual merge conflict | Re-plan with explicit owner in `analysis.md`; verified-merge.sh aborts rebase + surfaces |
| Post-merge verify breaks main | revert + auto-fix PR fires | Review the auto-fix PR; `decisions.log` has timestamp |
| AI mediation can't resolve | mediation exits non-zero | Human review; check `verified-merge-<stream>-<ts>.log` |
| Stream session orphaned by daemon crash | `claude agents` shows it stopped, no clean handoff | `claude respawn <id>` or `/swarm:respawn <stream>` |
| Coordinator session loses state | fleet.json out of sync with `claude agents --json` | Run `/swarm:status` — it reconciles |
| Stream stuck > 30 min, no commits | session hit a loop (workflow-state hook should warn) | `/swarm:stop <stream>` then `/swarm:respawn` with refined brief |
| Token budget exhausted | stream session ends mid-task | Increase `--max-budget-usd` in `/swarm:dispatch` |

## References

- Native CLI reference: https://code.claude.com/docs/en/cli-reference
- `claude --bg`: https://amux.io/guides/claude-code-headless/
- automazeio/ccpm: file-ownership rule for shared files
- obra/superpowers/skills/using-git-worktrees: native-first principle
- fengshao1227/ccg-workflow: task.json schema
- ChristopherKahler/paul: subagent six-gate criteria (in `.claude/skills/dispatch-criteria/`)
