---
name: flag-kill
description: Emergency flag rollback during a P1 incident.
metadata:
  type: playbook
status: established
created: 2026-05-28
last_verified: 2026-05-28
---

# Playbook: Emergency flag rollback

> Use during a P1 incident when a flagged feature is the suspected cause. Flag flip is the fastest, safest rollback.

## Decision tree

```
P1 incident detected
   │
   ├── Is the suspected cause a recently-ramped flag?
   │     ├── YES → /rollback-flag <name> (this playbook)
   │     └── NO → check deploy log; if recent deploy, /rollback (code path)
   │
   ├── Multiple flagged features ramped recently?
   │     ├── YES → start with the most recent ramp; kill one at a time
   │     └── NO → kill the suspected one
   │
   └── No flag is the cause?
         └── Fall back to `.claude/memory/playbooks/rollback.md` (code revert)
```

## Steps

### Step 0 — IS IT GATED?
Before anything else, check if the suspect feature is flag-gated. If it is, **the flag flip is your first move** — much faster than a code revert.

```bash
# Find the flag from spec/initiative
grep -r 'flag.name' specs/active/ initiatives/active/
```

### Step 1 — Flip the flag
```bash
/rollback-flag <name>
```
This:
- Flips flag to 0% in <60 seconds
- Opens incident automatically
- Pings Slack #incidents
- Logs to flag-kill-log.md

### Step 2 — Verify symptom gone
- Watch error rate dashboard for 5 minutes
- Confirm: error rate returns to baseline
- Confirm: no new related alerts firing

If symptom persists after 10 min → the flag wasn't the cause. Move to `rollback.md` (code revert) playbook.

### Step 3 — Triage
```bash
/incident-start "flag <name> rolled back at HH:MM: <symptom>"
```
- Assign IC, scribe, comms
- Status update to #incidents every 15 min
- Decide: hotfix-and-re-ramp vs. revert + rethink

### Step 4 — Post-mortem within 24h
```bash
/lesson-learned --category incident "flag <name> rollback"
```
Capture:
- Why the flag exposed the bug
- Why pre-prod testing missed it
- Whether the auto-rollback threshold was set correctly (would it have caught this if set tighter?)
- Action items: tighter monitoring, smaller initial %, additional test coverage

### Step 5 — Re-ramp (after fix)
- Start at 1% (NOT where you were before kill)
- Tighter monitoring window
- Tighter auto-rollback threshold for this flag specifically

## Anti-patterns

- **Don't `git revert` first.** It takes a full deploy cycle. Flag flip takes seconds.
- **Don't skip the postmortem.** Even if the fix is "obvious", capture the lesson.
- **Don't re-ramp to your previous %.** Start over at 1%; trust must be re-earned.
- **Don't kill multiple flags simultaneously.** Kill one, verify, then decide on the next.

## References

- See also: `.claude/memory/playbooks/rollback.md` (code-revert path)
- See also: `.claude/memory/playbooks/incident-response.md` (full IC playbook)
- See also: `.claude/skills/flag-rollout/SKILL.md` (post-incident re-ramp)
