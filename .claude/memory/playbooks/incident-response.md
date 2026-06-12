---
name: incident-response
description: Live incident command — severity matrix, IC/scribe/comms roles, status update cadence, communication templates.
metadata:
  type: playbook
status: established
created: 2026-05-28
last_verified: 2026-05-28
---

# Playbook: Live incident response

> Different from `rollback.md` (which is a tactic). This is the *process* — who does what, in what cadence, with what comms.

## Severity matrix

| Severity | Definition | Page? | Status update cadence |
|---|---|---|---|
| **P1** | Customer impact > 1% of users; revenue loss; data integrity at risk | Immediate, all-channels | Every 15 min until resolved |
| **P2** | Customer impact < 1%; degraded experience; high error rate | Business hours; off-hours if persistent | Every 30 min during impact |
| **P3** | Internal-only; specific user reports; non-urgent regression | Next business day | At kickoff + at resolution |

## Roles (assigned at incident-start)

1. **IC (Incident Commander)** — owns the response; makes calls; not hands-on with code
2. **Scribe** — captures timeline; writes status updates; sets up the doc
3. **Comms** — talks to customers / support / status page
4. **Subject-matter** — hands-on engineer doing the actual investigation/fix

For P3: IC alone is often enough. For P2: IC + Scribe. For P1: all four.

## Process

### 0. Detect → declare

**Two tracks run in PARALLEL (Round 12):**

**Human track (the IC process — this playbook):**
- Alert fires (PagerDuty via Alertmanager `severity:page`) OR customer report OR internal observation
- On-call evaluates severity
- `/incident-start --severity P1 "<one-line symptom>"` opens the incident
- IC drives mitigation FIRST (rollback / flag-kill) — stop the bleeding before the fix-forward

**Factory track (the autonomous hotfix loop — fix-forward):**
- The same alert also fires `repository_dispatch: prod-alert` → `hotfix-ingest.yml`
- `hotfix-to-task.sh` queues a `priority: hotfix` task at the TOP of `tasks/TASKS.md` (dedup-guarded)
- A `claude --bg` session runs debugger Phase 0 (recall prior incidents + Sentry fingerprint history) → diagnose → fix → evidence bundle → **PR (never auto-merged)**
- The IC reviews the factory's PR alongside their own mitigation

These don't conflict: the human stops the bleeding (mitigation/rollback), the factory prepares the reviewed fix-forward. For SEV1, the IC may merge the factory's PR once mitigation is stable; for SEV2 the factory's PR often lands first.

### 1. Triage (first 5 min)
- Skim recent deploys (`/audit-trail` last 30 min)
- Skim recent flag changes
- Skim Sentry top errors
- IC assigns roles
- Scribe creates incident doc in `.claude/memory/incidents/active/<id>.md`

### 2. Stabilize (next 10-15 min)
- **Step 0 (always): is this flag-gated?** If yes → `/rollback-flag` first.
- Otherwise: deploy rollback → `git revert` → DB rollback (in that order)
- Aim: stop the bleeding before diagnosis
- Status update to #incidents

### 3. Diagnose
- After stabilization, IC + SME find root cause
- `/debug` skill or debugger agent (which consults Sentry MCP for prior errors)
- Scribe captures timeline + decisions

### 4. Fix forward (or stay rolled back)
- If fix is small + safe: ship via hotfix branch (release-eng playbook)
- If fix is risky: stay rolled back; address in next normal cycle

### 5. Close
- `/incident-end` marks incident resolved
- Status update: "Resolved. Postmortem within 24h."
- Move incident doc from `active/` to `closed/`

### 6. Postmortem (within 24h)
- `/lesson-learned --category incident`
- Blameless; focus on system, not people
- Action items: each has owner + due date
- Action items become tasks in `tasks/TASKS.md` with `priority: incident-followup`

## Status update template

```
[<HH:MM>] [<SEVERITY>] <one-line summary>

Status: Investigating | Identified | Mitigating | Resolved
What we know: <facts>
What we're doing: <current action>
ETA to next update: <time>
IC: @<name>
```

## Communication templates (per audience)

### Internal (Slack #incidents)
Use status update template. Frequent, factual, no speculation.

### Customer (status page)
- "We're investigating an issue affecting <feature>. Updates every <N> minutes."
- "We've identified the cause and are working on a fix."
- "The fix is rolling out. We expect normal service in <time>."
- "Resolved. Postmortem to follow."

### Executive (private channel)
- Higher signal-to-noise: severity, customer impact, ETA, who's involved, ask (if any)

## Hard rules

- **Don't debug before stabilizing.** Stop the bleeding first. Investigation can wait.
- **Don't multi-task IC and SME.** Roles are separate for a reason.
- **Don't fix forward into the same flag.** If a flag-gated feature caused the incident, stay rolled back; don't ramp again until root cause is fully understood.
- **Don't skip the postmortem.** Every P1 + P2 gets one within 24h, blameless.

## References

- Google SRE Workbook — Incident Response
- PagerDuty Incident Response Documentation
- `.claude/memory/playbooks/rollback.md`
- `.claude/memory/playbooks/flag-kill.md`
- `.claude/commands/incident-start.md`, `/incident-end.md`
