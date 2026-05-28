---
description: Sunset a feature, service, or product surface. 90-day decommission with user notification, traffic ramp-down, data archival, and final removal. Different from /deprecate-api which is for API contracts; this is for full surface sunset.
argument-hint: "<feature-name> [--reason <text>] [--horizon 90d|180d]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, WebFetch
disable-model-invocation: true
---

# /sunset — Decommission a feature

```bash
feature="$1"
reason="${2:-no longer strategic}"
horizon="${3:-90d}"

# 1. Verify low usage via PostHog/Pendo MCP
echo "Querying feature usage for last 90d..."
usage=$(claude -p "Query PostHog MCP for users active on feature \"$feature\" in the last 90 days" --bare)
echo "Current usage: $usage"

# 2. Create the sunset announcement
mkdir -p .claude/memory/sunsets
sunset_doc=".claude/memory/sunsets/$(date +%Y-%m-%d)-${feature}.md"
sunset_date=$(date -d "+${horizon}" '+%Y-%m-%d' 2>/dev/null || date -v "+${horizon}" '+%Y-%m-%d')

cat > "$sunset_doc" <<EOF
---
feature: $feature
reason: "$reason"
announced: $(date -Iseconds | head -c 10)
sunset_date: $sunset_date
status: announced
---

# Sunset: $feature

## Why
$reason

## Timeline (${horizon} from announce)

Week 0 (announced): notification banner in-app for affected users; email to last 90d active users
Week 4: read-only mode; new signups disabled
Week 8: data export available; users migrate to <replacement or alternative>
Week 12 (sunset): feature returns 410 Gone; UI removed; backend deleted

## Affected users
$usage

## Replacement / alternative
(if any)

## Action items
- [ ] In-app banner with sunset date  — week 0
- [ ] Email notification to active users  — week 0
- [ ] Disable new signups  — week 4
- [ ] Export tool available  — week 8
- [ ] Final email warning  — week 11
- [ ] Sunset (code/data removal)  — week 12
- [ ] Postmortem  — week 13

## References
- Spec / initiative that introduced this feature: <link>
- Spec / initiative that supersedes (if any): <link>
EOF

echo "Sunset announcement: $sunset_doc"
echo "Action: announce via #announcements, email, status page, changelog"
echo "Sunset date: $sunset_date"

# 3. Open tasks
{
  echo "- [ ] T-sunset-${feature}-week0  | priority: sunset  | due: $(date '+%Y-%m-%d')"
  echo "  summary: Announce sunset for $feature (in-app banner + email)"
  echo
  echo "- [ ] T-sunset-${feature}-week12  | priority: sunset  | due: $sunset_date"
  echo "  summary: Final removal of $feature code + data"
} >> tasks/TASKS.md
```

## Hard rules

- **Minimum 90-day horizon** for any user-facing sunset. Less is ambush.
- **Always offer an alternative or replacement.** "Just stop using it" is not a migration path.
- **Track usage to zero before final removal.** Don't sunset a feature 100 users still actively rely on.
- **Final removal includes data archival decision.** GDPR / data-retention compliance.
- **Postmortem after sunset.** Document what we learned about lifecycle/usage.

## References

- Stripe API deprecation policy (canonical industry reference)
- See also: `/deprecate-api`, `.claude/memory/deprecations/REGISTRY.md`

$ARGUMENTS
