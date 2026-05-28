---
description: Aggregate everything a new (or returning) engineer needs to know about ONE feature/area — spec, plan, ADRs, incidents, patterns, recent PRs, runbook. Closes the "month-14 hire onboarding" gap.
argument-hint: "<feature-id-or-area>"
allowed-tools: Read, Glob, Grep, Bash, WebFetch
disable-model-invocation: true
---

# /context-pack — Onboard onto a feature area

`/onboard` is first-day-of-job. `/context-pack` is "you're picking up feature 142 today."

```bash
target="$1"

# 1. Resolve target → spec / plan / area
spec_file=$(ls specs/active/${target}*.md specs/archive/${target}*.md 2>/dev/null | head -1)
plan_file=$(ls plans/active/${target}*.md plans/archive/${target}*.md 2>/dev/null | head -1)

if [ -z "$spec_file" ]; then
  echo "# Context pack for area: $target"
  echo
  echo "No matching spec — searching for path/keyword..."
  area="$target"
else
  echo "# Context pack: $(basename "$spec_file" .md)"
  area=$(grep -E '^slug:' "$spec_file" | sed 's/^slug: //')
fi

# 2. Spec + plan
echo
echo "## Spec"
[ -f "$spec_file" ] && cat "$spec_file"
echo
echo "## Plan"
[ -f "$plan_file" ] && cat "$plan_file"

# 3. Related ADRs
echo
echo "## Related ADRs"
grep -rl "$area\|$target" .claude/memory/decisions/ 2>/dev/null | while read f; do
  echo "### $(basename "$f")"
  awk '/^---$/{c++;next} c==1' "$f"  # frontmatter
  echo
  grep -A3 '^## Decision' "$f" | head -5
  echo
done

# 4. Related incidents
echo
echo "## Related incidents"
grep -rl "$area\|$target" .claude/memory/incidents/ 2>/dev/null | while read f; do
  echo "- $(basename "$f")"
  grep -E '^- (Date|Severity|Root cause):' "$f"
done

# 5. Related patterns
echo
echo "## Patterns relevant to this area"
grep -rl "$area\|$target" .claude/memory/patterns/ 2>/dev/null | while read f; do
  echo "- $(basename "$f"): $(head -3 "$f" | tail -1)"
done

# 6. Recent PRs touching this area
echo
echo "## Recent PRs (last 90 days)"
if [ -f "$spec_file" ]; then
  gh pr list --state merged --search "Spec: $spec_file" --limit 10 --json number,title,mergedAt 2>/dev/null \
    | jq -r '.[] | "- PR #\(.number) — \(.title) (merged \(.mergedAt))"'
fi

# 7. Runbook (if a service)
echo
echo "## Runbook"
runbook=$(ls docs/runbooks/*${target}*.md 2>/dev/null | head -1)
if [ -n "$runbook" ]; then
  echo "See: $runbook"
fi

# 8. Owner + on-call
if [ -f "$spec_file" ]; then
  echo
  echo "## Owner / on-call"
  grep -E '^(owner|human_owner|on_call):' "$spec_file"
fi

# 9. Open tasks for this area
echo
echo "## Open tasks"
grep -B0 -A5 "spec:${target}" tasks/TASKS.md 2>/dev/null | head -50

# 10. Quickstart commands
echo
echo "## Quickstart"
echo "  /implement T-<id>   — pick up the next task"
echo "  /verify             — run the journey for this feature"
echo "  /debug              — if you hit a bug"
```

## When to use

- New hire picks up a feature 6+ months into the project
- Returning engineer after parental leave / long PTO
- Cross-team handoff: team A built it, team B owns it now
- Postmortem investigation: "what was the original design intent?"

## What goes in vs. what stays out

**In** the context pack:
- The spec + plan
- Decisions taken (ADRs that reference this area)
- Past incidents in this area
- Patterns relevant
- Recent merged PRs
- Runbook + owner

**Out**:
- Unrelated decisions
- Old PRs that don't touch this area
- The entire codebase (use `Read`/`Grep` for that)

$ARGUMENTS
