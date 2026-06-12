# Autopilot — overnight unattended builds

> Configure once. Wake up to shipped features. Context stays clean via auto-dream.

## Prerequisites — read first

Before reading further, confirm you have these. **Skipping this section will cost 20+ minutes of frustration when configuration fails halfway through.**

| Requirement                               | Why                                                                                                 | How                                                                                              |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| **Anthropic Build plan or higher**        | Cloud Routines require this — Pro doesn't have them                                                 | Upgrade at https://claude.com/plans                                                              |
| **Claude.ai login** (not just API key)    | Routines run on Anthropic infra, authenticated via OAuth                                            | `claude login`                                                                                   |
| **GitHub OAuth connector** in claude.ai   | The routine opens PRs via GitHub on your behalf                                                     | Settings → Connections → GitHub                                                                  |
| **Branch protection on `main`**           | Routine pushes to `claude/overnight-*` and merges via PR; main must require reviews + status checks | `gh api repos/:owner/:repo/rulesets --method POST --input .github/rulesets/main-protection.json` |
| **At least one CI run on `main`**         | Required-check names must exist before you can reference them in the ruleset                        | Trigger via empty commit + push                                                                  |
| **`ANTHROPIC_API_KEY` in GitHub Secrets** | Used by the claude-code-action workflows                                                            | `gh secret set ANTHROPIC_API_KEY`                                                                |

If any of these aren't set up yet, do them now — it's faster than debugging a failed first run.

## What this gives you

- **23:00 daily** — a fresh Cloud sandbox spins up
- Picks unblocked tasks from `tasks/TASKS.md`
- Runs strict TDD per task via `/verify-loop` (autopilot skill inside)
- Verification gate refuses to mark "done" without evidence
- Self-heal on failures (max 3 attempts → escalate)
- WIP-checkpoint every 5-15 min — crash-safe
- Opens one PR per task on `claude/overnight-<date>-T-<id>`
- `/dream` consolidates memory before exit
- `OVERNIGHT_REPORT.md` at repo root summarizing everything
- Slack ping with one-screen summary (if connector enabled)

## The architecture

```
23:00 ┌─────────────────────────────────────────────────┐
      │  CLOUD ROUTINE fires on Anthropic infra         │
      │  ───────────────────────────────────────────    │
      │  Fresh git clone in disposable sandbox          │
      │  Auto Mode ON (Sonnet 4.6 classifier per call)  │
      │  PreToolUse hooks fire FIRST — exit 2 blocks    │
      │  Two safety layers; zero user prompts           │
      └────────────────────┬────────────────────────────┘
                           │
                           ▼
                  /verify-loop skill
                           │
        ┌──────────────────┴──────────────────┐
        │                                     │
        ▼                                     ▼
   per task:                       at end (any stop):
   - autopilot 5 phases            - /dream skill
   - verify-before-completion      - OVERNIGHT_REPORT.md
   - self-heal max 3               - PRs opened
   - WIP checkpoints               - Slack ping
   - PR on completion              - exit cleanly
```

## Setup (one-time, ~10 minutes)

### 1. Configure Cloud Routine

Go to **https://claude.ai/code/routines** → New Routine.

Open `.claude/routines/overnight-build.yml` and paste each field into the form:

- **Name**: `overnight-build`
- **Schedule**: `0 23 * * *` UTC (adjust TZ)
- **Repo URL**: your GitHub repo
- **Branch base**: `main`
- **Permission mode**: `auto` (Sonnet 4.6 classifier — no user prompts, no bypass)
- **Model**: `claude-opus-4-8` (fallback Sonnet 4.6)
- **Budgets**: the single source of truth is the `budgets:` block in
  [`.claude/routines/overnight-build.yml`](../.claude/routines/overnight-build.yml)
  (`max_wall_clock_minutes`, `max_budget_usd`, `max_turns`). This doc deliberately
  does not restate the numbers — change them in the YAML and they take effect; a
  number copied here would only drift. (AC-12)
- **Connectors**: GitHub (required) + Slack (recommended)
- **Branch permission**: `claude/overnight-*` (the routine can only push here)
- **Env**:
  - `ENABLE_TOOL_SEARCH=true`
  - `CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000`
- **Prompt body**: copy the multi-line `prompt:` from the YAML file

### 2. Test with "Run now"

Click "Run now" on the routine. Watch for ~10 minutes:

- A new session should appear in your Claude.ai sidebar
- `claude agents` from your local repo (next morning) should show the run's daughter sessions
- After completion, `OVERNIGHT_REPORT.md` should appear at repo root in a PR

### 3. Wire local backstop (Desktop dream-cron at 03:00)

For nights when the Cloud Routine doesn't run (Anthropic outage, expired auth, etc.):

```bash
bash .claude/scripts/install-overnight-tasks.sh
```

This installs a local Desktop scheduled task that runs `/dream` at 03:00 daily.

### Routine installation matrix

Every routine the harness ships, where it runs, how it gets installed, and what silently degrades
if you skip it. `bash .claude/scripts/install-overnight-tasks.sh` registers all desktop routines in
one pass and records successes to `.claude/state/routines-installed` (which `harness-doctor.sh`
diffs against `.claude/routines/*.yml` to warn about gaps).

| Routine                     | Schedule             | Surface                      | Installed by                                           | If skipped                                                                   |
| --------------------------- | -------------------- | ---------------------------- | ------------------------------------------------------ | ---------------------------------------------------------------------------- |
| `overnight-build`           | 23:00 daily          | **Cloud Routine** (claude.ai) | Manual: https://claude.ai/code/routines (§1 above)     | No autonomous overnight work at all — the core autopilot loop never runs     |
| `overnight-build-backstop`  | 23:30 daily          | Desktop                      | `install-overnight-tasks.sh`                           | Cloud Routine outage = silent overnight skip, no alert                        |
| `dream-cron`                | 03:00 daily          | Desktop                      | `install-overnight-tasks.sh`                           | Memory never consolidates — observations pile up, instincts never extracted  |
| `gc-nightly`                | 02:30 daily          | Desktop                      | `install-overnight-tasks.sh`                           | TASKS.md, verify/, logs, MEMORY.md grow unbounded                             |
| `oq-aging`                  | 06:00 daily          | Desktop                      | `install-overnight-tasks.sh`                           | Week-old `[OQ]`s rot silently; blocked specs never escalate                   |
| `quarterly-archive`         | 02:00 first Mon of Q | Desktop                      | `install-overnight-tasks.sh`                           | specs/plans archives never rotate; active dirs bloat                          |
| `appetite-circuit-breaker`  | 09:00 daily          | Desktop                      | `install-overnight-tasks.sh`                           | Initiatives blow past 50%/100% appetite with no flag                          |
| `atlas-refresh`             | 04:00 daily          | Desktop                      | `install-overnight-tasks.sh`                           | Codebase atlas drifts stale; agents navigate from outdated structure          |
| `constitution-compact-cron` | 04:00 quarterly      | Desktop                      | `install-overnight-tasks.sh`                           | Constitution creeps past the 300-line cap until validate.sh hard-fails        |
| `feedback-triage`           | Mon 08:00 weekly     | Desktop                      | `install-overnight-tasks.sh`                           | Feedback entries accumulate unranked; no weekly triage report                 |
| `feedback-poll`             | hourly               | Desktop (needs source creds) | `INSTALL_FEEDBACK_POLL=yes install-overnight-tasks.sh` | Customer-signal intake stays manual                                           |
| `hotfix-sentry-poll`        | every 10 min         | Desktop (needs Sentry MCP)   | `INSTALL_SENTRY_POLL=yes install-overnight-tasks.sh`   | Prod SEV1/SEV2 errors never auto-create hotfix tasks                          |

(`cost-report`, also registered by the installer, is a scheduled task without a routine yml — it
feeds `pre-spawn-cost-gate` from `.claude/hooks/.log/cost-summary.json`.)

### 4. Slack ping (optional)

In the routine config, enable the Slack connector. The autopilot prompt already includes the ping instruction. You'll get a single message at end-of-run.

## Permission model — Auto Mode + Hooks (two safety layers, zero prompts)

| Surface                             | Mode                | Why safe                                                                                                                                                                                                                                     |
| ----------------------------------- | ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cloud Routine sandbox (11 PM)       | `auto`              | Sonnet 4.6 classifier reviews every tool call. PreToolUse hooks fire FIRST (exit 2) hard-blocking `rm -rf`, force-push to main, secrets, `DROP TABLE`. Two layers, no prompts. Disposable sandbox means even a slip can't reach your laptop. |
| Your laptop interactive             | `acceptEdits`       | Standard. Asks for any unknown command. Use `/fewer-permission-prompts` (Boris #81) to tune from transcripts.                                                                                                                                |
| Local `--bg` sessions               | `auto`              | Anthropic classifier on every tool call. Runs in worktree. Same as Cloud but on your machine.                                                                                                                                                |
| Desktop scheduled task (3 AM dream) | `auto`              | Even though /dream only touches `.claude/memory/`, we use Auto Mode for consistency.                                                                                                                                                         |
| CI containers (Docker, single-use)  | `bypassPermissions` | Only context where bypass is appropriate — ephemeral container, container exit destroys all state.                                                                                                                                           |

**Why Auto Mode over bypassPermissions:** The classifier catches things the hook denylist might miss (novel injection vectors, unfamiliar dangerous combos like `chmod 777 ~/.ssh/`). Latency cost is ~200-500ms per tool call, negligible for an overnight run. `"disableBypassPermissionsMode": "disable"` is set in `settings.json` to prevent accidental bypass — note the **string** `"disable"`, not a boolean: Claude Code silently ignores `true`/`false` forms, so the boolean spelling would leave bypass enabled while looking locked.

**Order of safety checks (in any mode):**

1. PreToolUse hook (`.claude/hooks/pre-bash-guard.sh`, `.claude/hooks/pre-write-secret-scan.sh`) → exit 2 hard-blocks
2. settings.json `deny` list → matched patterns blocked
3. (Auto Mode only) Sonnet 4.6 classifier → reviews remaining calls
4. (other modes only) User prompt
5. Tool executes

## Branch-protection guard rails

Set these on your GitHub repo before relying on autopilot:

- **Required reviews**: 1 human OR Claude code-reviewer + Claude security-reviewer (via `.github/workflows/`)
- **Required status checks**: `ci`, `claude-code-review`, `claude-code-security-review`, `e2e-preview`
- **Restrict push to default**: no one pushes directly to `main`
- **Branch-name pattern protection**: `main`/`master` are protected; `claude/overnight-*` is allowed for PRs only

The routine cannot bypass these because GitHub enforces them at the API layer.

## What goes wrong (and how to debug)

| Symptom                               | Likely cause                                      | Fix                                                                                                   |
| ------------------------------------- | ------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Routine doesn't fire at 23:00         | TZ misconfigured                                  | Check routine schedule TZ in claude.ai UI                                                             |
| Routine fires but exits in 30 seconds | Permission hooks blocked something Phase 0 needed | Check `.claude/hooks/.log/` in the resumed session; widen hook allowlist or relax the offending guard |
| Routine runs but no PRs               | `gh` auth missing inside Routine                  | Re-link GitHub connector in claude.ai → Routines → settings                                           |
| `OVERNIGHT_REPORT.md` missing         | Run hit budget cap before end                     | Increase `max_wall_clock_minutes` or trim task scope per night                                        |
| Same task escalates every night       | Underlying spec ambiguous or test broken          | Open the spec, run `/clarify`, fix `[OQ]` items, mark task `pending` again                            |
| `/dream` didn't run                   | Stop hook missed it OR cron-backstop also failed  | Manually invoke `/dream` next session; check `.claude/memory/.cache/.dream-state.json`                |

## Sample morning routine (your habit)

1. ☕
2. Open Slack → read the autopilot ping ("3 shipped, 1 escalated")
3. Open repo → read `OVERNIGHT_REPORT.md` (one screen)
4. Open PRs tab → review each `claude/overnight-*` PR
5. Merge what looks good (CI is already green from claude-review + claude-security)
6. For the 1 escalated task: open the spec, address the diagnosed issue, mark `pending`
7. Total time: 15-30 minutes

## What it costs

A typical overnight run (duration bounded by `max_wall_clock_minutes` in the routine):

- **Tokens**: 1-3M total (Opus 4.8 ~1M, Sonnet 4.6 ~1.5M, Haiku 4.5 ~0.5M for subagents)
- **USD**: illustrative $15-30 per run; the hard cap is `max_budget_usd` in the routine config
- **Anthropic plan**: Build plan or higher (Routines require Claude.ai login, not raw API key)

## References

- Cloud Routines: https://code.claude.com/docs/en/routines
- Desktop scheduled tasks: https://code.claude.com/docs/en/desktop-scheduled-tasks
- /loop: https://code.claude.com/docs/en/scheduled-tasks
- mvara-ai/precompact-hook (witness brief pattern)
- grandamenium/dream-skill (consolidation pattern)
- obra/superpowers/skills/verification-before-completion (the gate)

## Sandbox (runtime)

The overnight/autonomous run is contained by the **OS-level runtime sandbox**, launched via the `--sandbox` flag (or the routine sandbox setting) — NOT by any `permissions.sandbox` key in `settings.json` (that key is not part of the settings schema and is silently ignored). Configure the sandbox + network egress allow-list at the routine/launch layer for your environment.
