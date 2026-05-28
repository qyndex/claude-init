# GitHub Issue projection + lifecycle

Round 11. How the factory's task ledger projects onto GitHub Issues + a Projects v2 board, with TODO→DOING→DONE→SHIPPED automation — **without** creating a second source of truth.

## The architecture in one sentence

`tasks/TASKS.md` is the **sole source of truth** for task state (offline, deterministic, append-only); GitHub Issues are a **write-only projection** of *specs* (the human-meaningful unit), with full lifecycle automation riding on git/PR/deploy events.

## What becomes an issue (and what doesn't)

| Harness artifact | GitHub representation |
|---|---|
| **Spec** (`specs/active/<id>.md`) | One **Issue** (type: Feature), title `[feat] <id> <slug>` |
| **Phase** (L/XL specs) | A **sub-issue** of the spec issue |
| **Task** (`tasks/TASKS.md` entry) | A **checklist line** inside the spec issue body — NOT its own issue |
| **Initiative** | An issue (type: Feature/epic) with specs as sub-issues |
| **Incident** | An Issue (type: Bug, `[incident]` form) |
| **Debt item** (`[!]`/`[s]`) | An Issue (type: Task, `[debt]` form) |
| **Standalone chore/spike** | An Issue (file directly via form) |

**Why not issue-per-task?** The planner decomposes specs into 2-5 minute atomic tasks. 200 of those as issues = noise + a network call in the autonomous inner loop (which must stay offline so `verify.sh`'s local red→green ledger stays authoritative). Tasks appear as a checklist in their spec's issue — full traceability, zero inner-loop network.

## One-time setup (per repo/org)

### 1. Create the org issue types (GA)
Settings → Organization → Issue types. Enable defaults (Task, Bug, Feature) + add as needed. (Requires `admin:org`.)

### 2. Create the Projects v2 board
- New Project (board layout)
- Add a single-select **Status** field with options EXACTLY: `TODO`, `DOING`, `DONE`, `SHIPPED`
- Note the project number + the Status field's option IDs (needed by the lifecycle workflow):
  ```bash
  gh project field-list <project-number> --owner <org> --format json \
    | jq '.fields[] | select(.name=="Status")'
  ```
- Store the IDs as repo variables (Settings → Secrets and variables → Actions → Variables):
  `PROJECT_ID`, `STATUS_FIELD_ID`, `STATUS_TODO`, `STATUS_DOING`, `STATUS_DONE`, `STATUS_SHIPPED`

### 3. Wire the issue templates
- The forms in `.github/ISSUE_TEMPLATE/` reference `OWNER/PROJECT_NUMBER` — replace with your real values (a `sed` one-liner in setup.sh handles this).

### 4. Enable the built-in auto-add (belt + suspenders)
Project → Workflows → "Auto-add to project" filtered to this repo. Our explicit Action (issue-lifecycle.yml) is the authority; this just catches anything filed outside the projector.

## Lifecycle mapping

| Status | Trigger | Driven by |
|---|---|---|
| **TODO** | spec issue created / all tasks `[ ]` | tasks-to-issues.sh projection |
| **DOING** | first task `[~]` OR a linked PR opens | issue-lifecycle.yml on `pull_request: opened` |
| **DONE** | all tasks `[x]` + PR merged (verified locally via TDD ledger) | issue-lifecycle.yml on `pull_request: closed (merged)` → explicit `updateProjectV2ItemFieldValue` |
| **SHIPPED** | feature flag reaches 100% (Round 4 flag-rollout) — falls back to deploy-success | `/flag` at 100% → fires a `repository_dispatch`; OR `deployment_status: success` |

**DONE ≠ SHIPPED on purpose**: DONE means the code is written, verified, and merged. SHIPPED means it's actually in users' hands (flag at 100%). A phased rollout sits at DONE for days/weeks before SHIPPED.

## Traceability

- Every PR body carries `Closes #<spec-issue>` (auto-added by `collect-evidence.sh` / release agent).
- Every commit carries an `Issue: #<n>` trailer (CLAUDE.md §VI).
- The evidence bundle (Round 10) references the spec issue; `evidence-gate` requires the link.
- Sub-issue progress bars show task-checklist completion at a glance.

## Human board moves are advisory

If a human drags a card, the projector (next sync) **re-asserts TASKS.md state** and posts a comment noting the human's intent. The ledger always wins. There is **no** code path that reads task state back from GitHub — `no-issue-authority.yml` CI-guards this (fails the build if introduced). This is the load-bearing safety property: it keeps the autonomous offline loop free of a hard network dependency.

## When sync runs

Never in the inner loop. Only at network boundaries:
- **PR-time** — `/ship` / release agent runs `tasks-to-issues.sh <spec-id>` (already online to open the PR)
- **Coordinator merge** — when a swarm stream's verified-merge lands
- **Manual** — `/issues sync [spec-id]`

Each sync is idempotent: it regenerates the full checklist + Status from TASKS.md rather than patching, so concurrent swarm streams converge instead of racing.

## Rate limits

The projector serializes writes and honors `Retry-After`. The real ceiling is GitHub's secondary limit of 500 content-creations/hour; a typical run touches <20 issues, well under. Big initial backfills should run `tasks-to-issues.sh --all --throttle`.

## Setup checklist

- [ ] Org issue types enabled
- [ ] Projects v2 board with TODO/DOING/DONE/SHIPPED Status
- [ ] Repo variables: PROJECT_ID, STATUS_FIELD_ID, STATUS_* option IDs
- [ ] `OWNER/PROJECT_NUMBER` replaced in `.github/ISSUE_TEMPLATE/*.yml`
- [ ] `gh auth status` shows `project` scope (for the projector)
- [ ] First backfill: `bash .claude/scripts/tasks-to-issues.sh --all`
