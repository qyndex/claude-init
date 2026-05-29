---
description: "Mark a spec as superseded by a new one. Cascades: links PRs already merged under the old spec, opens cleanup/revert decision tasks, updates initiative spec catalog."
argument-hint: "<old-spec-id> --by <new-spec-id>"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, TodoWrite
disable-model-invocation: true
---

# /supersede — Spec supersession workflow

```bash
old_id="$1"
new_id="$2"    # --by <new-spec-id>

# 1. Find both specs
old_spec=$(ls specs/active/${old_id}*.md 2>/dev/null | head -1)
new_spec=$(ls specs/active/${new_id}*.md 2>/dev/null | head -1)

if [ -z "$old_spec" ]; then
  echo "Old spec $old_id not found in specs/active/"
  exit 1
fi
if [ -z "$new_spec" ]; then
  echo "New spec $new_id not found in specs/active/"
  exit 1
fi

# 2. Update frontmatter on both
sed -i.bak "s/^status:.*/status: superseded/" "$old_spec"
sed -i.bak "s/^superseded_by:.*/superseded_by: ${new_id}/" "$old_spec"
sed -i.bak "s/^supersedes:.*/supersedes: ${old_id}/" "$new_spec"
rm -f "${old_spec}.bak" "${new_spec}.bak"

# 3. Find PRs merged under the old spec
echo "## PRs merged under superseded spec $old_id"
gh pr list --state merged --search "Spec: specs/active/${old_id}" --json number,title,mergedAt | jq -r '.[] | "- PR #\(.number) — \(.title) (merged \(.mergedAt))"'

# 4. Open decision tasks
echo "## Action items for superseded PRs"
echo "For each merged PR under $old_id, decide:"
echo "  (a) Keep — code still useful in new spec; carry forward"
echo "  (b) Revert — incompatible with new direction; open revert PR"
echo "  (c) Dormant — keep but flag-disabled; remove on cleanup"
echo "  (d) Refactor — adapt to new spec's shape"

# Open one tracking task per merged PR
gh pr list --state merged --search "Spec: specs/active/${old_id}" --json number | jq -r '.[].number' | while read pr; do
  cat >> tasks/TASKS.md <<EOF
- [ ] T-supersede-${old_id}-pr${pr}  | priority: supersede-cleanup  | created: $(date -Iseconds)
  summary: Decide disposition for PR #${pr} (was under superseded spec ${old_id})
  files: <decide via review>
  accept: human decision recorded in .claude/memory/decisions/
  owner: @<spec-owner>
EOF
done

# 5. Update initiative spec catalog if both belong to one
init=$(grep -l "spec.*$old_id\|spec.*$new_id" initiatives/active/*.md 2>/dev/null | head -1)
if [ -n "$init" ]; then
  echo "Update $init spec catalog manually (or via /initiative status)"
fi

# 6. Move old spec to archive after a grace period
echo "Old spec stays in specs/active/ with status=superseded until disposition decisions complete."
echo "Run /cleanup after all supersede-cleanup tasks close — old spec auto-archives."

# 7. Log the supersession
echo "$(date -Iseconds) supersede ${old_id} → ${new_id}" >> .claude/memory/decisions.log
```

## When to supersede vs. amend

| Change | Action |
|---|---|
| Small correction to an unshipped spec | Edit in place (status stays `draft`) |
| Significant pivot before any code ships | Edit in place; bump `updated` |
| Pivot after some PRs already merged | **/supersede** — preserves history |
| Total rewrite of approach | **/supersede** |
| Same scope, new owner/team | Edit `human_owner` frontmatter |

## Hard rules

- **Always link via frontmatter.** `superseded_by:` on old, `supersedes:` on new. Git history alone doesn't survive copy-paste.
- **Always open disposition tasks** for already-merged PRs. Don't assume "keep" — force a decision.
- **Don't immediately delete the old spec.** Status=superseded keeps it discoverable; archive after disposition closes.
- **Note in the initiative.** If both specs are under an initiative, update the spec catalog.

$ARGUMENTS
