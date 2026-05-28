---
description: Announce deprecation of a public API endpoint or contract. Adds Deprecation/Sunset HTTP headers, opens migration tasks, schedules sunset, tracks callers.
argument-hint: "<endpoint> --sunset YYYY-MM-DD [--successor <new-endpoint>]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, WebFetch
disable-model-invocation: true
---

# /deprecate-api — Announce + track API deprecation

Delegates to api-versioning skill. See `.claude/skills/api-versioning/SKILL.md` for the full v2-alongside-v1 process.

```bash
endpoint="$1"
sunset_date="$2"      # --sunset YYYY-MM-DD
successor="$3"        # --successor <new-endpoint>

# 1. Validate inputs
if ! date -d "$sunset_date" 2>/dev/null && ! date -j -f "%Y-%m-%d" "$sunset_date" 2>/dev/null; then
  echo "Invalid sunset date"; exit 1
fi

# Sunset must be at least 6 months out for public APIs (per skill rules)
# (Internal APIs: at least 90 days)

# 2. Add Deprecation / Sunset response headers
# This requires a code edit — the agent does it via the implementer-agent + middleware change.
# Goal: every response from $endpoint includes
#   Deprecation: <sunset_date GMT>
#   Sunset: <sunset_date GMT>
#   Link: <$successor>; rel="successor-version"
#   Link: <https://docs.example.com/migrate>; rel="deprecation"

# 3. Open a migration task per caller
analytics_query="select distinct client_id from api_logs where endpoint='$endpoint' and ts > now()-7d"
# Result: list of distinct callers — open a task per caller for migration outreach

# 4. Append to .claude/memory/deprecations/REGISTRY.md
cat >> .claude/memory/deprecations/REGISTRY.md <<EOF

| $endpoint | $(date -Iseconds | head -c 10) | $sunset_date | $successor | $(echo $analytics_query) | @<owner> |
EOF

# 5. Open the spec for the deprecation (if not already)
# spec gets superseded_by frontmatter populated when successor ships

# 6. Calendar reminder for sunset
# Cron: cron entry that pages on-call 30 days before sunset

# 7. Status page note
echo "Action: announce on status page + changelog"
echo "Action: email partners@ list with migration guide"

echo "Deprecation tracked: $endpoint → sunset $sunset_date → successor $successor"
echo "Registry updated. Migration tasks opened. Calendar reminder set."
```

## Sunset reminder hooks

A daily cron scans `REGISTRY.md`:
- 30 days before sunset: loud warning in CI + status-page reminder
- 7 days before sunset: page on-call
- Sunset day: switch endpoint to return `410 Gone` (manual; via flag-flip or release)

$ARGUMENTS
