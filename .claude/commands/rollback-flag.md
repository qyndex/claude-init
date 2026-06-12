---
description: Emergency flag rollback. Flip flag to 0% in <60 seconds. Use during a P1 incident when a flagged feature is the suspected cause. Fastest, safest rollback path — preferred over `git revert` for any flagged change.
argument-hint: "<flag-name> [--no-confirm]"
allowed-tools: Bash, Read, Edit, Write
disable-model-invocation: true
---

# /rollback-flag — Emergency kill

The fastest rollback in a flagged world is a flag flip. **Always try this before `git revert`** if the change is flag-gated.

## Process

```bash
flag="$1"

# 1. Mechanical kill (e2e-audit release-deploy-4): provider adapters live in the
#    script — launchdarkly | posthog | unleash | webhook, selected by FLAG_PROVIDER.
#    Exit 0 = killed + logged. Exit 2 = provider unwired/failed — KILL MANUALLY NOW,
#    do not proceed to step 2 until the flag is confirmed off.
bash .claude/scripts/rollback-flag.sh "$flag" --reason "${2:-incident}"

# 2. Verify via the provider (read-back), then open the incident if not already open
if [ -z "$(ls .claude/memory/incidents/active/ 2>/dev/null)" ]; then
  claude -p "/incident-start \"flag $flag rolled back: <symptom>\"" --bare
fi

# 3. Slack page (if Slack MCP active)
claude -p "Post to Slack #incidents: 'Flag $flag rolled back at $(date). Symptom: ...'" --bare
```

The script already appends to `.claude/memory/playbooks/flag-kill-log.md` and marks the
flag KILLED in `.claude/memory/flags/REGISTRY.md`. The same script is the first responder
in `canary-deploy.yml` (SLO-breach path) and `hotfix-ingest.yml` (alert → flag-gated spec),
so a metric breach produces a mechanical kill without any human or LLM in the loop.

## Hard rules

- **Don't `git revert` first.** The flag flip is faster, safer, and doesn't require a deploy.
- **Don't ask for confirmation in incident mode.** Add `--no-confirm` if invoked during an active page.
- **Log everything.** The flag-kill log is the audit trail for post-incident review.
- **Open an incident.** A flag rollback is always interesting enough to need a postmortem.
- **Update the spec's status.** The flag's spec moves from `shipping` → `paused` until the bug is fixed.

## Order of preference for rollback

1. **Flag flip (this command)** — seconds
2. **Re-deploy previous binary** — minutes
3. **`git revert` + new deploy** — 15-60 minutes
4. **Database rollback** — last resort; only if data is corrupted

Always exhaust 1 before considering 2-4.

## What to do next

- `/incident-start` if not already open
- Investigate via `/debug` (consults Sentry MCP for prior error patterns)
- Fix forward; redeploy; re-ramp via `/flag ramp <flag>` with smaller %s and tighter monitoring

$ARGUMENTS
