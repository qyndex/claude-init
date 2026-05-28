---
description: Find orphan artifacts — decisions, specs, tasks owned by departed engineers. Surface for re-assignment. Run when someone leaves the team.
argument-hint: "<departed-handle> [--reassign-to @<new-owner>]"
allowed-tools: Read, Glob, Grep, Bash, Edit
disable-model-invocation: true
---

# /owner-walk — Re-assign work from departed engineers

```bash
departed="$1"
new_owner="$2"    # --reassign-to @<new>

if [ -z "$departed" ]; then
  echo "Usage: /owner-walk @<departed-handle> [--reassign-to @<new>]"
  exit 1
fi

echo "# Owner walk: $departed"
echo

# 1. Specs
echo "## Specs"
grep -l "human_owner.*$departed\|owner.*$departed" specs/active/*.md specs/archive/*.md 2>/dev/null

# 2. Plans
echo
echo "## Plans"
grep -l "owner.*$departed" plans/active/*.md plans/archive/*.md 2>/dev/null

# 3. Decisions (ADRs)
echo
echo "## Decisions"
grep -l "Deciders.*$departed\|owners.*$departed" .claude/memory/decisions/*.md 2>/dev/null

# 4. Initiatives
echo
echo "## Initiatives"
grep -l "owner.*$departed\|sponsor.*$departed" initiatives/active/*.md initiatives/archive/*.md 2>/dev/null

# 5. Tasks
echo
echo "## Tasks"
grep -n "owner.*$departed" tasks/TASKS.md 2>/dev/null

# 6. Reassign if requested
if [ -n "$new_owner" ] && [[ "$new_owner" == "--reassign-to" ]]; then
  new="$3"
  echo
  echo "## Reassigning all to $new"
  files=$(grep -rl "$departed" .claude/memory specs initiatives plans tasks 2>/dev/null)
  for f in $files; do
    sed -i.bak "s/$departed/$new/g" "$f" && rm -f "${f}.bak"
    echo "  ✓ Updated $f"
  done
fi
```

$ARGUMENTS
