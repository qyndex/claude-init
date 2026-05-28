---
description: Close an active incident. Captures duration, marks resolved, moves doc to closed/, schedules postmortem within 24h, updates status page. Last command on-call runs before standing down.
argument-hint: "<incident-id> [--resolution <text>]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, TodoWrite
disable-model-invocation: true
---

# /incident-end — Close a live incident

```bash
id="$1"
resolution="$2"

# 1. Find the active incident doc
incident_doc=$(ls .claude/memory/incidents/active/${id}*.md 2>/dev/null | head -1)
if [ -z "$incident_doc" ]; then
  echo "No active incident with id $id"
  exit 1
fi

# 2. Append closing entries
{
  echo
  echo "## Closing"
  echo "- $(date -Iseconds) — resolved"
  echo "- Resolution: ${resolution:-fix-forward; details in postmortem}"
  echo "- Duration: TBD (compute from opened_at)"
  echo
  echo "## Postmortem"
  echo "Due within 24h. Run: /lesson-learned --category incident --id $id"
} >> "$incident_doc"

# 3. Update frontmatter status → resolved
sed -i.bak 's/^status:.*/status: resolved/' "$incident_doc" && rm "$incident_doc.bak"

# 4. Move to closed/
mkdir -p .claude/memory/incidents/closed
mv "$incident_doc" .claude/memory/incidents/closed/

# 5. Status page
echo "Update status page: 'Resolved. Postmortem to follow.'"

# 6. Slack
claude -p "Post to Slack #incidents: 'Incident $id resolved. Postmortem in 24h.'" --bare

# 7. Create the postmortem task
echo "- [ ] T-postmortem-$id  | priority: incident-followup  | due: $(date -d '+24 hours' -Iseconds 2>/dev/null || date -v +24H -Iseconds)" >> tasks/TASKS.md

echo "Incident $id closed."
echo "Next: /lesson-learned --category incident --id $id (within 24h)"
```

## Hard rules

- **Don't close prematurely.** "We rolled back" is not "resolved" if the symptom can return.
- **Always schedule the postmortem.** Within 24h. No exceptions.
- **Status page must reflect.** Customers need to see "Resolved."

$ARGUMENTS
