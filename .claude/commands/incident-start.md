---
description: Open a live incident. Assigns IC, creates incident doc, pages on-call, posts to #incidents, pulls recent deploys + flag changes + top Sentry errors for triage. The first command on-call runs.
argument-hint: "--severity P1|P2|P3 \"<one-line symptom>\""
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, TodoWrite, WebFetch
disable-model-invocation: true
---

# /incident-start — Open a live incident

```bash
# Parse args
sev="$1"           # --severity P1|P2|P3
summary="$2"       # one-line

# 1. Create incident doc
id="$(date +%Y%m%d-%H%M%S)"
mkdir -p .claude/memory/incidents/active
incident_doc=".claude/memory/incidents/active/${id}-$(echo "$summary" | tr ' /' '-_' | head -c 40).md"

cat > "$incident_doc" <<EOF
---
id: $id
severity: $sev
summary: "$summary"
status: investigating
opened_at: $(date -Iseconds)
ic: TBD
scribe: TBD
comms: TBD
sme: TBD
---

# Incident: $summary

## Timeline
- $(date -Iseconds) — opened, severity $sev

## Status updates

## Investigation

## Mitigation

## Root cause

## Action items
EOF

# 2. Pull triage context
echo "## Recent deploys (last 30 min)" >> "$incident_doc"
gh run list --workflow=ci.yml --limit 5 --json conclusion,createdAt,headSha,name >> "$incident_doc" 2>/dev/null

echo "## Recent flag changes" >> "$incident_doc"
# Query flag provider MCP
claude -p "Query the flag provider MCP for changes in the last 1 hour. Return as a markdown table." --bare >> "$incident_doc" 2>/dev/null

echo "## Top Sentry errors (last 30 min)" >> "$incident_doc"
# Query Sentry MCP
claude -p "Query Sentry MCP for top exception classes in the last 30 minutes." --bare >> "$incident_doc" 2>/dev/null

# 3. Assign roles (interactive)
# Prompt user for IC/Scribe/Comms/SME

# 4. Page on-call (if P1)
if [ "$sev" = "P1" ]; then
  echo "Pinging @oncall on Slack..."
  claude -p "Post to Slack #incidents: 'P1 INCIDENT OPENED: $summary. IC needed. See $incident_doc'" --bare
fi

# 5. Open incident channel
echo "Open Slack channel: #incident-$id"

# 6. Set status page (if customer-affecting)
if [ "$sev" = "P1" ] || [ "$sev" = "P2" ]; then
  echo "Update status page: 'Investigating issue with <feature>'"
fi

echo "Incident opened: $incident_doc"
echo "Next: assign roles, follow .claude/memory/playbooks/incident-response.md"
```

$ARGUMENTS
