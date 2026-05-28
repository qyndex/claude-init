---
description: Enforce ADR supersession. Find dead ADRs (status=superseded but still in active context), validate that superseded_by points to a real ADR, surface ADRs that haven't been verified in >12 months.
argument-hint: "[--prune-stale] [--verify-links]"
allowed-tools: Read, Glob, Grep, Bash
disable-model-invocation: true
---

# /adr-walk — Supersession enforcement

```bash
mode="${1:---verify-links}"

echo "# ADR walk — $(date -Iseconds)"

# 1. Find ADRs with status: superseded
echo
echo "## Superseded ADRs"
grep -rl '^- \*\*Status\*\*:.*superseded' .claude/memory/decisions/ 2>/dev/null | while read f; do
  id=$(basename "$f" .md)
  target=$(grep -E '^- \*\*Status\*\*:' "$f" | sed -E 's/.*superseded by (ADR-[0-9]+).*/\1/' | head -1)
  echo "- $id → $target"

  # 2. Verify target exists
  if [ -n "$target" ]; then
    if ! ls .claude/memory/decisions/*"${target}"*.md >/dev/null 2>&1; then
      echo "  ⚠ Target ADR $target NOT FOUND"
    fi
  fi
done

# 3. Find ADRs accepted >12mo ago without last_verified field
echo
echo "## ADRs needing re-verification (accepted > 12mo, no recent last_verified)"
year_ago=$(date -d '1 year ago' +%s 2>/dev/null || date -v -1y +%s)

for f in .claude/memory/decisions/*.md; do
  [ -f "$f" ] || continue
  status=$(grep -E '^- \*\*Status\*\*:' "$f" | head -1)
  if echo "$status" | grep -q 'accepted'; then
    # Check last_verified field
    last_v=$(grep -E '^- \*\*last_verified\*\*:|^last_verified:' "$f" | head -1)
    if [ -z "$last_v" ]; then
      date_field=$(grep -E '^- \*\*Date\*\*:' "$f" | head -1 | sed -E 's/.*Date\*\*: ([0-9-]+).*/\1/')
      if [ -n "$date_field" ]; then
        decided_at=$(date -d "$date_field" +%s 2>/dev/null || date -j -f '%Y-%m-%d' "$date_field" +%s 2>/dev/null)
        if [ -n "$decided_at" ] && [ "$decided_at" -lt "$year_ago" ]; then
          echo "- $(basename "$f") (decided $date_field; no last_verified)"
        fi
      fi
    fi
  fi
done

# 4. Find orphan superseded_by chains
echo
echo "## Chains (decision A superseded by B superseded by C...)"
echo "Walking forward references..."
# (heuristic; full chain walk left to manual)

# 5. Surface to architect agent
echo
echo "## Recommendation"
echo "The architect agent should now FILTER OUT superseded ADRs when reading the decision store"
echo "(see .claude/agents/core/architect.md updated workflow)"

if [ "$mode" = "--prune-stale" ]; then
  echo
  echo "## Pruning superseded ADRs older than 1 year to archive..."
  archive_dir=".claude/memory/.archive/decisions-$(date +%Y%m)"
  mkdir -p "$archive_dir"
  grep -rl '^- \*\*Status\*\*:.*superseded' .claude/memory/decisions/ 2>/dev/null | while read f; do
    if [ "$(find "$f" -mtime +365 -print 2>/dev/null)" != "" ]; then
      mv "$f" "$archive_dir/"
      echo "Archived $f"
    fi
  done
fi
```

## Hard rules

- **An ADR can't supersede a non-existent ADR.** Broken `superseded_by` references are bugs.
- **Active "accepted" ADRs need re-verification** if >12 months old (add `last_verified: YYYY-MM-DD` field on the template).
- **The architect agent filters superseded** before consulting decisions (see updated agent prompt).

$ARGUMENTS
