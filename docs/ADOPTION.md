# Brownfield Adoption Guide

> How to bring an **existing / legacy project** under the factory — safely. The factory is great
> at greenfield (see [STARTING-PROMPT.md](STARTING-PROMPT.md)); this guide is for a repo that
> already has code, history, docs, its own conventions, maybe its own `.claude/` setup, and very
> possibly legacy/untested/vulnerable code you can't just let an agent loose on.
>
> **The governing principle:** *no tests = no writes.* The factory will NOT autonomously modify
> untested legacy code. Adoption is six **human-gated** phases that earn that trust one zone at a
> time. Nothing touches your code until you approve Phase 1.

---

## When to use this (vs. greenfield)

| You have… | Use |
|---|---|
| An empty repo / brand-new idea | [STARTING-PROMPT.md](STARTING-PROMPT.md) or `/kickoff` |
| An existing codebase (any age, any state) | **this guide → `/adopt`** |

Signals you're brownfield: existing source with git history, an `architecture.md`/ADRs/PRD, a
backlog in markdown or GitHub Issues, an existing `CLAUDE.md`/`AGENTS.md`, legacy or vulnerable
dependencies, code on obsolete tech you may need to migrate.

---

## Step 0 — Install the harness (without clobbering theirs)

The factory `.claude/` must be in the repo before `/adopt` exists. **Never `cp -nr` over an
existing `.claude/`** — that leaves a half-merged mess. Two cases:

**A) Repo has no `.claude/` (clean install):**
```bash
git clone <factory-repo> /tmp/claude-init
git -C /tmp/claude-init archive HEAD | tar -x -C .   # into your repo (git-aware: tracked files only)
bash .claude/scripts/setup.sh
```

**B) Repo already has its own `.claude/` / `CLAUDE.md` (reconcile):**
```bash
git clone <factory-repo> /tmp/claude-init
bash /tmp/claude-init/.claude/scripts/reconcile-claude-dir.sh --from /tmp/claude-init --into .
# → backs up your .claude/ to .brownfield-backup/<ts>/ (repo root, auto-gitignored, with a
#   MANIFEST.txt of every created path), installs the factory (process) files + the .github
#   gate layer (no-clobber; collisions become [OQ]s), PRESERVES your settings.local.json /
#   state / memory / rules / secrets, saves your CLAUDE.md to .claude/CLAUDE.md.brownfield-orig,
#   and drafts AGENTS.md from your conventions.
bash .claude/scripts/setup.sh   # (now finds the factory CLAUDE.md; the brownfield guard passes)
```
`setup.sh` refuses to run greenfield over a foreign `CLAUDE.md` — it points you here. Override only
with `FORCE_GREENFIELD=1` if you truly mean greenfield.

---

## Let Claude drive it — `/adopt auto` (recommended)

You don't have to run all six phases by hand. Tell Claude to drive, and it self-drives the
mechanical phases while **hard-stopping only at the two safety gates** — Phase 1 (review the
archaeology report) and Phase 4 (review the characterization tests). Everything else (extract
conventions, import docs/issues, build the backlog, hand off) it does and auto-advances.

```text
/adopt auto        # runs Phase 1 (archaeology) → STOPS at safety gate 1
#   ↳ review ADOPTION-REPORT.md + the legacy-safety globs
/adopt approve 1
/adopt auto        # auto-runs phases 2–3 (reconcile + import) → STOPS at safety gate 4
#   ↳ Claude writes characterization tests for the hotspots; you review them
/adopt approve 4
/adopt auto        # auto-runs phases 5–6 (backlog + handoff) → DONE
```

Two human decisions instead of six. The hard `verify.sh` characterization gate still backstops
everything — even under `auto`, the factory cannot modify untested legacy. Or kick the whole thing
off with one prompt: *"Adopt this repo with `/adopt auto`; stop and show me what you found at each
safety gate before I approve."*

Prefer full control? Run the phases one at a time instead (below).

## The six phases

Run them in order (or let `/adopt auto` chain them). Each STOPS and waits for `/adopt approve <n>`.
Check progress anytime with `/adopt status`.

### Phase 1 — Archaeology  ·  `/adopt start`  *(READ-ONLY)*
Builds an honest picture without touching code: repo atlas (stack/structure), churn×LOC
**hotspots** (most-changed, largest files — your highest-risk zones), dependency + vulnerability
scan, a test/coverage baseline, and the **legacy-safety manifest** (`.claude/state/adopt/uncharacterized-paths.txt`)
which initially marks *every* source zone off-limits to autonomy. Output: **`ADOPTION-REPORT.md`**.
→ Read it, resolve every `[OQ]`, then `/adopt approve 1`.

### Phase 2 — Reconcile  ·  `/adopt reconcile`
Extracts your project conventions into **`AGENTS.md`** + a path-scoped rule (a *draft* — refine it).
Surfaces any `.claude/` collisions as `[OQ]`s. **One source of truth per axis:** the factory
`CLAUDE.md` owns *process* (the 8-phase workflow, commit protocol, gates); your project facts
(stack, test/lint commands, domain non-negotiables) live in `AGENTS.md`. Conflicts are never
silent-merged — you decide via `/clarify`.
→ Refine `AGENTS.md`, resolve `[OQ]`s, then `/adopt approve 2`.

### Phase 3 — Import  ·  `/adopt import`
Brings your existing knowledge + backlog in:
- **Docs/ADRs/PRD/architecture** → copied (referenced, *not* lossy-converted) into
  `.claude/memory/decisions/imported/` + indexed.
- **GitHub Issues** → a **one-time** migration (`import-issues-once.sh`): open issues become
  pending tasks in `tasks/TASKS.md` (tagged `imported_from_issue: #N`), closed issues become
  history in memory. It **self-terminates** via a committed sentinel and never runs again — going
  forward, `tasks/TASKS.md` is the sole source of truth and issues are a *write-only* projection
  (see [ISSUE-LIFECYCLE.md](ISSUE-LIFECYCLE.md)). This is the one sanctioned read of issue state.
→ Triage the imported backlog, then `/adopt approve 3`.

### Phase 4 — Baseline safety  ·  `/adopt baseline`  *(the heart of it)*
The factory earns the right to touch legacy code by first **characterizing** it. Using the
[`characterize` skill](../.claude/skills/characterize/SKILL.md), write characterization (golden-master)
tests for the hotspots — they pin *current* behavior (bugs included). As each zone gains a
characterization test, remove its glob from `uncharacterized-paths.txt`. Record the real coverage
floor.
→ When hotspots are characterized, `/adopt approve 4`.

### Phase 5 — Remediation backlog  ·  `/adopt backlog`
Turns the report's vuln/security/legacy-debt findings into prioritized tasks, each tagged with a
**migration strategy**: `strangler-fig` (replace a module/service behind a facade),
`expand-contract` (zero-downtime DB/API change), `codemod` (>50 call sites), `sprout-method` (new
behavior added beside untested legacy, never inside it).
→ Review the backlog, then `/adopt approve 5`.

### Phase 6 — Handoff  ·  `/adopt handoff`
Seeds stack patterns, projects tasks→issues, marks adoption complete. The repo now uses the
standard 8-phase workflow ([OPERATOR-MANUAL.md](OPERATOR-MANUAL.md)).
→ `/triage` to see the combined backlog, or `/implement next`.

---

## How autonomy stays safe on your legacy

This is the whole point. After Phase 1, three mechanisms enforce *no tests = no writes*:

1. **`verify.sh` characterization gate** — FAILS any change to a file under a glob in
   `.claude/state/adopt/uncharacterized-paths.txt` that lacks a characterization test. (Human
   override: `SKIP_CHAR_GATE=1` — never used by autopilot.)
2. **Autopilot skip** — the overnight run SKIPS any task whose files touch a flagged zone, logging
   `ADOPT-BLOCKED`, until you've characterized it.
3. **You lift it deliberately** — removing a glob from the manifest is an explicit choice you make
   once a zone is safe.

So the overnight autopilot can grind your *new* (sprouted) work and your *characterized* zones, but
it physically cannot wander into raw untested legacy.

---

## FAQ / gotchas

**"Can I let autopilot run mid-adoption?"** Yes — it will safely skip flagged zones and work on
anything characterized or new. The pre-flight prints which zones remain blocked.

**"The issue import didn't run / I want to re-run it."** It self-terminates after one
*successful* run (`.claude/state/adopt/issues-imported.done`). A failed `gh` read (auth, network,
rate-limit) errors out loudly WITHOUT writing the sentinel — fix `gh auth status` and re-run; open
imports are deduped, so re-running after a partial failure is safe. Re-running after success is
forbidden by design (it would duplicate + risk inverting the authority model). To deliberately
re-migrate, delete the sentinel. `/adopt auto` refuses to auto-approve Phase 3 when the import errored.

**"It refused to read my issues for status."** Correct — that's `no-issue-authority`. Task state
comes from `tasks/TASKS.md`, never the GitHub API. The one-time import is the *only* sanctioned
read, and it's a migration, not a sync.

**">500 issues?"** `import-issues-once.sh --limit <N>` (default 500). Very large backlogs may need
pagination — confirm before Phase 3.

**"My repo has no conventional `src/` root."** Phase 1 notes this; edit
`uncharacterized-paths.txt` in Phase 2 to list your real source globs.

**"Reverting adoption."** Everything destructive is backed up to `.brownfield-backup/<ts>/` (repo
root, auto-gitignored) and your originals are kept as `*.brownfield-orig`. The backup's
`MANIFEST.txt` lists every path adoption created or overwrote. Undo with
`bash .claude/scripts/reconcile-claude-dir.sh --revert <ts>` — it restores your original `.claude/`
and deletes the manifest-listed created files (scaffold, .github gates, .mcp.json, …).

**"Upgrading an already-adopted repo to a newer harness."** Re-run reconcile with `--upgrade`:

```bash
git -C /tmp/claude-init archive HEAD | tar -x -C /tmp/factory   # or any clone of the new factory
bash .claude/scripts/reconcile-claude-dir.sh --from /tmp/factory --into . --upgrade
bash .claude/scripts/setup.sh
```

Default (adoption) reconcile no-clobbers `commands/`, `hooks/`, and `.github/` so it never
touches a file you might have authored — but that also means it won't *update* factory-owned
files on a re-run. `--upgrade` flips this for **factory-owned** files only: a same-named file
the factory ships (e.g. `hooks/pre-bash-dep-freshness.sh`, `commands/swarm/*`,
`.github/workflows/evidence-gate.yml`, `docs/AUTOPILOT.md`) is refreshed to the new version
(backed up first, change reported); files the factory does **not** ship (your own `/deploy`
command, custom hooks, custom workflows) are still preserved. Your `specs/`, `plans/`, `tasks/`,
and application source are never touched. Everything overwritten lands in
`.brownfield-backup/<ts>/` (now covering `.claude/`, `.github/`, and `docs/`), so the change is
reversible. After upgrading, run `bash .claude/scripts/validate.sh` — remaining failures are your
project's own corpus drift, not the upgrade.

---

## Wiring customer-feedback intake (optional, post-adoption)

The feedback pipeline ships **configured but unwired** (gap-audit G60): the
`feedback-poll.yml` routine and `/feedback` command exist, but every source
connector is a catalogue entry. Until wired, intake is manual (`/feedback log`)
and `/harness-doctor` reports "feedback intake configured but UNWIRED". To wire:

1. Copy the relevant block (fireflies / intercom / pendo / slack) from
   `_disabled_examples` into `mcpServers` in `.mcp.json`; add credentials via
   env vars (never in the repo tree).
2. Paste `.claude/routines/feedback-poll.yml` into a Cloud Routine
   (claude.ai/code/routines) — it needs the connectors, so Desktop-local won't do.
3. Schedule `.claude/routines/feedback-triage.yml` (weekly, Desktop is fine) —
   ranking is deterministic via `.claude/scripts/feedback-score.sh`.
4. ARR/renewal fields are **operator-supplied** unless you wire a billing source
   (Stripe MCP or `.claude/memory/feedback/accounts.csv`); the scorer warns when
   most entries lack `arr_band`.

## See also
- [OPERATOR-MANUAL.md](OPERATOR-MANUAL.md) — running the factory day-to-day (post-adoption)
- [docs/research/brownfield-onboarding.md](research/brownfield-onboarding.md) — the research brief behind this design
- `.claude/commands/adopt.md` — the `/adopt` command
- `.claude/skills/characterize/SKILL.md` — characterization tests
- [ISSUE-LIFECYCLE.md](ISSUE-LIFECYCLE.md) — why issue import is one-time + write-only thereafter
