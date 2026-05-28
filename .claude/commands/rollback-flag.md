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

# 1. Confirm flag exists in provider
flag_state=$(claude -p "Query the flag provider MCP for current state of flag $flag" --bare)

# 2. Flip to 0% (kill)
# Provider-specific call via MCP
# OpenFeature: posthog/launchdarkly/unleash MCP

# 3. Verify
sleep 5
new_state=$(claude -p "Re-query flag $flag, confirm 0% / OFF" --bare)

# 4. Open incident if not already open
if [ -z "$(ls .claude/memory/incidents/active/ 2>/dev/null)" ]; then
  # spawn incident-start
  claude -p "/incident-start \"flag $flag rolled back: <symptom>\"" --bare
fi

# 5. Log to playbook
echo "$(date -Iseconds)  rollback-flag $flag  $(whoami)" >> .claude/memory/playbooks/flag-kill-log.md

# 6. Slack page (if Slack MCP active)
claude -p "Post to Slack #incidents: 'Flag $flag rolled back at $(date). Symptom: ...'" --bare
```

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
