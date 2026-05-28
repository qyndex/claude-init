# Operator Manual

> **Who this is for:** anyone on the team who will *run* this software factory — not edit its
> internals, but use it to ship real product. Read this once end-to-end (~20 min). Keep the
> [Runbook](#10-runbook-cookbook) open as a reference.
>
> **What this factory is:** an autonomous, AI-driven software development system. You give it
> direction and approve the gates that matter; it does the spec→plan→build→test→ship→operate work —
> through the day interactively, and overnight unattended — for a single feature or a multi-year
> product roadmap, shipping to production in safe phased increments.

---

## 1. The 60-second mental model

You are the **operator** — think product owner + engineering director. The factory is your
**autonomous engineering org**. You steer; it executes; you approve the few decisions that are
truly yours.

```
   YOU (intent, priorities, gate approvals)
        │
        ▼
  ┌───────────────────────────────────────────────────────────────┐
  │  THE FACTORY                                                    │
  │                                                                 │
  │  Idea ─▶ Roadmap ─▶ Spec ─▶ Plan ─▶ Tasks ─▶ Build(TDD) ─▶      │
  │            ▲                                       │            │
  │            │                                       ▼            │
  │         Learn ◀── Operate(SLOs) ◀── Ship(phased) ◀── Verify     │
  │            ▲                                                    │
  │            └──────────── customer feedback ────────────────────┘
  └───────────────────────────────────────────────────────────────┘
        │
        ▼
   Production (behind feature flags, ramped 1%→10%→50%→100%)
```

Three things make it trustworthy:

1. **Everything is written down before it's built.** Specs, plans, and tasks are files in the
   repo. Nothing is built from a vibe.
2. **Nothing is "done" without evidence.** Tests run red→green, the running app is exercised,
   screenshots/logs are captured, and an evidence bundle is attached to every PR.
3. **Humans hold the merge button and the production deploy.** The factory does the work and
   opens the PR; *you* approve the merge and the ramp.

---

## 2. Your role vs. the factory's role

| You own | The factory owns |
|---|---|
| What to build and why (intent, priorities) | How to build it (architecture, code, tests) |
| Approving specs with open questions | Drafting specs, plans, tasks |
| Approving merges to `main` | Running TDD, verification, security scans |
| Approving production deploys + flag ramps | Opening PRs with evidence bundles |
| Strategic pivots (drop/pause/supersede) | Detecting drift, stale deps, recurring incidents |
| Reviewing the overnight report each morning | Doing the overnight work, writing the report |
| Answering the factory's clarifying questions | Asking good questions *before* coding |

**Rule of thumb:** if a decision is reversible and mechanical, the factory makes it. If it's
irreversible, costly, or strategic, it stops and asks you.

---

## 3. The five ways you interact

| Mode | You do this when… | How |
|---|---|---|
| **Interactive session** | You want to drive step-by-step, or it's a brand-new area | Open Claude Code in the repo and talk to it; use slash commands |
| **Kickoff (new product)** | Starting from zero — no roadmap yet | Paste the [starting prompt](STARTING-PROMPT.md) or run `/kickoff`; it interviews you, then builds the roadmap |
| **Autopilot (overnight)** | You want work to continue while you sleep | A Cloud Routine runs at 23:00; you read `OVERNIGHT_REPORT.md` in the morning ([AUTOPILOT.md](AUTOPILOT.md)) |
| **Parallel swarm** | Many independent tasks at once | `/swarm` dispatches up to 10 background streams, each in its own worktree ([PARALLEL-SWARM.md](PARALLEL-SWARM.md)) |
| **Just approve gates** | The pipeline is humming; you only weigh in at decisions | Review PRs, answer questions, approve ramps |

Most teams use a blend: kickoff once, drive interactively for the hard parts, let autopilot grind
the backlog overnight, and use the swarm for big parallelizable pushes.

---

## 4. A day in the life

A realistic day operating the factory on an established product:

**08:30 — Read the overnight report.** Open `OVERNIGHT_REPORT.md` at the repo root. It lists what
shipped (with PR links), what escalated (and why), decisions made (with commit SHAs), and open
questions for you. 5-minute read.

```
You:  /status
      → 3 PRs awaiting your review, 1 task escalated, flag `checkout-v2` at 10% (healthy)
```

**08:45 — Clear the review queue.** Each overnight PR has an evidence bundle in its body (AC
checklist, smoke output, screenshots, coverage). You read the evidence, not the diff line-by-line.
Approve the good ones; comment on the rest (the factory revises and re-pushes).

**09:30 — Triage.** `/triage` ranks the backlog and surfaces the one escalated task. You see it
failed three self-heal attempts on a gnarly race condition. You either give a hint and requeue it
(`requeue-failed.sh --reset T-91`) or hand it to yourself.

**10:00 — A customer signal lands.** A sales call flagged a churn risk. `/feedback triage` surfaces
it; you decide it's worth a feature and run `/initiative create … --from-feedback FB-…`. The
factory drafts the initiative and grills you on KR alignment.

**11:00 — Drive a new feature interactively.** `/specify "team billing dashboard"` → answer its
clarifying questions → `/plan` → `/tasks` → `/implement next`. You watch the first task go red→green
and then let it run.

**14:00 — A prod alert fires.** Sentry detects a spike. The hotfix pipeline auto-creates a
top-of-queue `priority: hotfix` task, an autonomous session reproduces it, fixes it, and opens a PR
with a regression test. You review and merge. (It never auto-merges a hotfix.)

**17:00 — Set the night's work.** Make sure the backlog has unblocked tasks. The 23:00 Cloud Routine
will pick them up. Laptop can be off.

You touched maybe 8 commands all day. The factory did hundreds of tool calls.

---

## 5. The eight-phase workflow

This is the spine. Each phase is a slash command/skill you invoke; the factory does the work and
stops at the gates that need you. (Full constitution: `.claude/CLAUDE.md` §VIII.)

| # | Phase | You type | What happens | Your gate |
|---|---|---|---|---|
| 1 | **Constitute** | `/constitution` | One-time: establishes house rules (already done in this template) | — |
| 2 | **Specify** | `/specify <feature>` | Drafts `specs/active/<id>.md`: problem, goals, user stories, acceptance criteria | Review goals |
| 3 | **Clarify** | `/clarify` | Resolves open questions `[OQ]` in the spec | **Answer questions** |
| 4 | **Plan** | `/plan <id>` | Drafts `plans/active/<id>.md`: architecture, data model, API, phases | Review approach |
| 5 | **Tasks** | `/tasks <id>` | Decomposes the plan into 2–5 min verifiable tasks in `tasks/TASKS.md` | — |
| 6 | **Analyze** | `/analyze <id>` | Cross-checks spec ↔ plan ↔ tasks for gaps/contradictions | — |
| 7 | **Implement** | `/implement next` | Strict TDD (red→green→refactor), one task at a time | — |
| 8 | **Verify→Review→Ship** | `/verify` `/review` `/ship` | Runs the app, captures evidence, reviews diff, opens PR, ramps the flag | **Approve merge + deploy** |

**The autopilot shortcut:** `/loop` wraps phases 5–8 and runs them until the verification gate
passes — that's what the overnight routine uses. You don't have to type each phase by hand.

**You can always go off-script.** "Fix the typo in the footer" doesn't need a spec. The workflow is
for non-trivial work; small surgical changes are just done.

---

## 6. The two big levers

### Autopilot (overnight, unattended)
A **Cloud Routine** runs at 23:00 in a fresh sandbox, picks unblocked tasks from `tasks/TASKS.md`,
runs the full TDD + verify + evidence flow, opens PRs on `claude/overnight-<date>` branches, runs
`/dream` to consolidate memory, and writes `OVERNIGHT_REPORT.md`. **It never merges or deploys** —
that's your morning review. A local backstop (`local-overnight-build.sh`) runs if the cloud routine
can't. Setup + safety: [AUTOPILOT.md](AUTOPILOT.md).

### Parallel swarm (many tasks at once)
`/swarm` plans independent task streams and dispatches each as a background session in its own git
worktree (up to 10). A **coordinator** monitors them and merges each via `verified-merge.sh` (rebase
onto already-merged siblings → integration test → AI-mediated conflict resolution → merge only when
clean → auto-revert if main breaks). Use it for big parallelizable backlogs. Details:
[PARALLEL-SWARM.md](PARALLEL-SWARM.md).

---

## 7. Where everything lives (source-of-truth map)

| Question | Look here |
|---|---|
| **What's the task state?** (the one true backlog) | `tasks/TASKS.md` — **sole** source of truth. GitHub Issues are a *write-only mirror* |
| What are we building? | `specs/active/*.md` (shipped → `specs/archive/`) |
| How will we build it? | `plans/active/*.md` |
| What's the multi-quarter program? | `initiatives/active/*.md` |
| What are the company objectives? | `OKRs.md`, `roadmap.md` |
| Did last night's work succeed? | `OVERNIGHT_REPORT.md` (repo root) |
| What proof do we have a feature works? | `verify/<date>-<feature>/` (evidence bundles, screenshots, logs) |
| What has the factory learned? | `.claude/memory/` (decisions/ADRs, patterns, incidents, post-mortems) |
| What customer signal came in? | `.claude/memory/feedback/` |
| The house rules | `.claude/CLAUDE.md` (the constitution) |

**The golden rule of state:** task status lives in `tasks/TASKS.md` and nowhere else. If a tool ever
needs to know "is task T-42 done?", it reads that file — never the GitHub API. (A CI guard,
`no-issue-authority.yml`, enforces this.)

Task state markers in `tasks/TASKS.md`:
`[ ]` pending · `[~]` in progress · `[x]` done · `[!]` failed (3 self-heals exhausted) · `[b]` blocked · `[s]` shipped.

---

## 8. Safety model (how it stays safe while unattended)

The factory runs in **Auto Mode**: a Sonnet classifier reviews every tool call and approves/denies
with no prompt to you. Underneath that, two more layers:

1. **Hooks fire FIRST and hard-block** (before the classifier even runs). Destructive operations are
   refused outright: `rm -rf`, `git push --force` to main, `DROP TABLE`, `--no-verify`, `curl|sh`,
   `eval`, secret-file writes (`.env`, `*.pem`, `*.key`, `*credentials*`). These can't be talked
   around — they exit non-zero before execution.
2. **The classifier** catches novel/ambiguous cases the patterns miss.

What this means for you:
- **The factory cannot leak your secrets** (deny-listed for read and write) or run obviously
  dangerous commands, even overnight.
- **It cannot modify its own constitution.** Editing `.claude/CLAUDE.md` is blocked as
  self-modification — a human must do that deliberately. (You'll see this if you ask it to.)
- **It cannot merge or deploy on its own.** PRs wait for you. Production deploys require explicit
  in-session confirmation.
- **It treats web pages, tickets, and customer quotes as untrusted data**, never as instructions.

**To override a block** (rare): do it yourself, or adjust `.claude/settings.json` /
`.claude/CLAUDE.md` deliberately as a human. The point is that overrides are conscious, not
accidental. Full checklist: `.claude/skills/security-guard/SKILL.md`.

---

## 9. Reading the signals

| Command / file | Tells you |
|---|---|
| `/status` | One-glance: PRs awaiting review, in-flight tasks, flag ramps, escalations |
| `/triage` | Ranked backlog + stale items + **failed `[!]` tasks awaiting a requeue decision** |
| `/health` · `/harness-doctor` | Is the harness itself healthy? (config, hooks, MCP servers) |
| `bash .claude/scripts/cost-report.sh month` | Anthropic spend vs. monthly cap |
| `OVERNIGHT_REPORT.md` | Last night: shipped / escalated / decisions / open questions |
| PR body (evidence bundle) | Per-AC ✓/✗ with the proving test, smoke output, screenshots, coverage |
| `/okrs` · `/roadmap` | Are we on track against objectives? |

---

## 10. Runbook (cookbook)

Concrete recipes. Copy-paste friendly.

### Start a brand-new product from zero
```
1. Open Claude Code in an empty (or template) repo.
2. Paste the kickoff prompt (docs/STARTING-PROMPT.md) or run:  /kickoff
3. Answer its interview (it uses the grill-me skill to pin down scope, users, constraints, success metrics).
4. It produces: roadmap.md + OKRs.md + the first initiative + the first spec(s).
5. Approve, then let it run phases or hand it to autopilot overnight.
```

### Adopt an existing (brownfield) project into the factory
```
# Install the harness (reconcile if the repo already has its own .claude/):
bash <factory-clone>/.claude/scripts/reconcile-claude-dir.sh --from <factory-clone> --into .
bash .claude/scripts/setup.sh
# Then the six human-gated adoption phases (full guide: docs/ADOPTION.md):
/adopt start      # Phase 1: read-only archaeology → ADOPTION-REPORT.md   → /adopt approve 1
/adopt reconcile  # Phase 2: extract conventions → AGENTS.md              → /adopt approve 2
/adopt import     # Phase 3: docs/ADRs → memory, issues → TASKS.md (once) → /adopt approve 3
/adopt baseline   # Phase 4: characterization tests for hotspots          → /adopt approve 4
/adopt backlog    # Phase 5: legacy/vuln/migration → tagged tasks          → /adopt approve 5
/adopt handoff    # Phase 6: join the normal workflow
```
*No tests = no writes:* until you characterize a legacy zone, the factory refuses to auto-modify it.

### Add a feature to an existing product
```
/specify "what you want"     # answer clarifying questions
/plan <id>                   # review the approach
/tasks <id>                  # auto-decomposed
/implement next              # TDD; repeat or /loop to autopilot phases 5–8
/verify  →  /review  →  /ship # approve the merge + ramp
```

### Check what's going on
```
/status            # the dashboard
/triage            # what to do next + what's stuck
```

### A task is stuck / failed (`[!]`)
```
/triage                                          # failed tasks are now surfaced here
bash .claude/scripts/requeue-failed.sh            # list them with summaries
# after you understand/fix the root cause:
bash .claude/scripts/requeue-failed.sh --reset T-42   # re-open it deliberately
```
(Failed tasks exhausted 3 self-heal attempts — they need a human decision, not a blind retry.)

### A production incident
```
# Automatic: a Sentry/SLO alert auto-creates a top-of-queue `priority: hotfix` task; an
# autonomous session reproduces → fixes → opens a PR with a regression test. You review + merge.
# Manual:
/incident-start    # opens an incident, pulls prior similar incidents from memory
# … fix via the normal flow …
/incident-end      # writes the post-mortem; recurring patterns become semgrep rules over time
```

### Ship to production safely (phased)
```
# /ship lands code DEFAULT-OFF behind a flag, then ramps:
#   staff → 1% → 10% → 50% → 100%, each with a monitoring window + auto-rollback on SLO breach.
/flag rollout <name>     # advance one stage when its exit gate is met
/rollback-flag <name>    # instant 0% if something's wrong (flag flip, no code revert)
```

### Change strategic direction
```
/pivot drop <init-id> --reason "…"        # fast cascade: stop streams, flip child specs
/pivot pause <init-id> --until <date>      # defer to a later quarter
/pivot supersede <id> --by <new-id>        # replace with a scoped-down successor
/abandon <init-id> --reason "…"            # deep: extract learnings + post-mortem before archive
```

### Customer signal → roadmap → shipped
```
/feedback log "verbatim quote" --account "Acme" --severity P1   # or auto-polled hourly
/feedback triage                                                 # scores + clusters; surfaces top signals
/initiative create <slug> --from-feedback FB-…                   # promote to a program
# … normal spec→ship flow … ; on ship, the FB auto-closes (post-ship-close-feedback.sh)
```

### Keep dependencies fresh & safe
```
# Automatic nightly (01:00 UTC): scans stale/vulnerable deps, opens a PR per stack with
# the bump + any fixes, all gates passing. You just review.
/deps-audit            # on-demand snapshot
/upgrade <pkg>         # guided single-package upgrade
```

### Control cost
```
bash .claude/scripts/cost-report.sh month     # spend vs. cap
# Raise the cap if needed:  export CLAUDE_MONTHLY_CAP_USD=<n>
# Spawns (overnight/swarm/hotfix) are refused at 100% of cap by a pre-spawn gate.
```

### Pause unattended work (e.g., during a strategic rethink)
```
/pivot stop      # writes a skip-flag; the overnight routine sees it and skips tonight
```

---

## 11. Troubleshooting / FAQ

**"The overnight run didn't happen."** Check: was there unblocked work in `tasks/TASKS.md`? Was the
monthly cost cap exhausted (`cost-report.sh`)? Is there a `/pivot stop` skip-flag in
`.claude/state/`? Did the Cloud Routine auth expire? The local backstop
(`local-overnight-build.sh`) covers cloud outages.

**"It asked me to approve something it usually does itself."** The classifier hit an ambiguous case
or you're near the cost cap. Read the reason; it's shown inline.

**"It refused to edit `.claude/CLAUDE.md`."** Correct — self-modification of the constitution is
blocked by design. Edit it yourself if you truly intend to change the house rules.

**"A PR is blocked by `evidence-gate`."** An acceptance criterion is unproven — there's no passing
test tagged to it, or the smoke run was red. The factory must add the proof before merge; this is
working as intended.

**"Two automations look like they ran at once."** They serialize on `tasks/TASKS.md` via a lock, and
crons are staggered. If you see a collision, run `/harness-doctor`.

**"How do I see why we decided X six months ago?"** `/audit-trail` and `.claude/memory/decisions/`
(ADRs). Every non-obvious choice cites a source.

**"Is my laptop required for overnight runs?"** No — the Cloud Routine runs in Anthropic's sandbox.
The laptop backstop is only a fallback.

---

## 12. Glossary

- **Spec** — what to build (problem + acceptance criteria). One feature.
- **Plan** — how to build it (architecture, phases).
- **Initiative** — a multi-quarter program of specs. Above the spec.
- **Task** — a 2–5 minute verifiable unit of work in `tasks/TASKS.md`.
- **Evidence bundle** — the proof attached to a PR (per-AC test results, smoke output, screenshots).
- **Flag (feature flag)** — a switch that lets code ship default-OFF and ramp to users gradually.
- **Autopilot** — the unattended overnight Cloud Routine.
- **Swarm** — parallel background sessions, one per task stream, each in its own worktree.
- **Hotfix loop** — prod alert → auto-task → autonomous fix → PR (you merge).
- **Auto Mode** — permission mode where a classifier approves tool calls without prompting you.
- **NEXUS handoff** — the structured YAML every subagent emits so work is traceable.
- **`/dream`** — nightly memory consolidation (compress, promote patterns, decay stale notes).
- **Escalation** — the factory hit its limit (e.g., 3 failed self-heals) and is surfacing to you.

---

## 13. Go deeper

- [STARTING-PROMPT.md](STARTING-PROMPT.md) — the first prompt for a new product
- [ADOPTION.md](ADOPTION.md) — bring an existing/legacy project under the factory (`/adopt`)
- [AUTOPILOT.md](AUTOPILOT.md) — overnight runs, setup, safety
- [PARALLEL-SWARM.md](PARALLEL-SWARM.md) — the feature-stream fleet
- [PLAYBOOK.md](PLAYBOOK.md) — operational recipes (deeper than the runbook above)
- [ARCHITECTURE.md](ARCHITECTURE.md) — the layered model
- [PROD-OBSERVABILITY.md](PROD-OBSERVABILITY.md) — SLOs, alerts, the hotfix loop
- [OBSERVABILITY.md](OBSERVABILITY.md) — factory tracing (Langfuse/OTEL)
- [ISSUE-LIFECYCLE.md](ISSUE-LIFECYCLE.md) — how tasks project to GitHub Issues
- [AUDIT-TRAIL.md](AUDIT-TRAIL.md) — "when did we decide X" recipes
- `.claude/CLAUDE.md` — the constitution (the law)
- `/onboard` — interactive guided tour of this repo
