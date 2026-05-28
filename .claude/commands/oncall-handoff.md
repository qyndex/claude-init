---
description: Produce an on-call shift handoff document. Active incidents, alerts firing past 24h, flag changes, pending pages, recently shipped features, hot zones. Run at the end of every shift.
argument-hint: "[--to @<incoming>]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, TodoWrite
disable-model-invocation: true
---

# /oncall-handoff — Shift handoff

Different from `/handoff` (which is for Claude sessions). This is for *humans* rotating on-call.

```bash
incoming="$1"

handoff_doc=".claude/memory/oncall-handoffs/$(date +%Y-%m-%d-%H%M)-$(whoami).md"
mkdir -p "$(dirname "$handoff_doc")"

cat > "$handoff_doc" <<EOF
# On-call handoff

**From**: @$(whoami)  **To**: $incoming
**Generated**: $(date -Iseconds)
**Coverage period**: <last shift start> — $(date +%Y-%m-%d)

## Active incidents
EOF

ls .claude/memory/incidents/active/ 2>/dev/null | while read f; do
  echo "- $f" >> "$handoff_doc"
done

cat >> "$handoff_doc" <<EOF

## Alerts that fired (last 24h)
$(gh run list --workflow=lighthouse.yml --limit 5 --json conclusion,name 2>/dev/null || echo "(no Lighthouse data)")
$(claude -p "Query Datadog/Sentry MCP for alerts fired in the last 24h" --bare 2>/dev/null || echo "(no alert data)")

## Flag changes (last 7 days)
$(claude -p "Query flag provider MCP for flags ramped, killed, or cleaned up in the last 7 days" --bare 2>/dev/null || echo "(no flag data)")

## Recently shipped (last 24h)
$(gh pr list --state merged --limit 10 --json title,mergedAt,number 2>/dev/null | jq -r '.[] | "- PR #\(.number) — \(.title)"' || echo "(no recent PRs)")

## Stale alerts (firing > 12h without ack)
$(claude -p "Query alerting platform for alerts firing without ack > 12h" --bare 2>/dev/null || echo "(check PagerDuty/OpsGenie)")

## Pending pages / escalations
- (manually fill if any)

## Hot zones (services with elevated errors)
$(claude -p "Query Sentry MCP for services with error rate > 2x baseline" --bare 2>/dev/null || echo "(check Sentry dashboard)")

## What I did this shift
- (fill from memory — major fires, decisions, ramps)

## What's coming up (next 24h)
- Scheduled deploys
- Planned flag ramps
- Known stress events (e.g., marketing campaign launch)

## Watch this
- (manually fill — soft signals that might break)
EOF

echo "Handoff doc: $handoff_doc"
echo
echo "Slack the link to @$incoming and ping in #oncall."
```

$ARGUMENTS
