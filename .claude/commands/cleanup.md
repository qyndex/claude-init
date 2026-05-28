---
description: Run the project cleanup playbook — archive completed specs/plans, prune dead branches, vacuum hook logs, refresh memory index. Read-modify on safe paths only; never touches code.
argument-hint: ""
allowed-tools: Bash, Read, Edit, Write, Glob
disable-model-invocation: true
---

# /cleanup — Project hygiene

Routine housekeeping. Safe to run weekly.

## Process

1. **Archive completed specs**: any spec in `specs/active/` whose plan has all tasks `[x]` → move to `specs/archive/`. Same for plans.
2. **Truncate hook logs**: `.claude/hooks/.log/*.log` larger than 5 MB → keep last 1000 lines, archive the rest.
3. **Prune merged local branches** (ask first): `git branch --merged main` minus `main` itself.
4. **Refresh memory index**: re-scan `.claude/memory/{decisions,patterns,incidents,playbooks}/` for new files and append missing entries to `MEMORY.md`.
5. **Compact TASKS.md**: move archive section overflow if file > 2000 lines.

## Steps

```!
echo "=== Hook log sizes ==="
ls -lh .claude/hooks/.log/ 2>/dev/null || echo "no logs"
```

```!
echo
echo "=== Specs ready to archive (all tasks complete) ==="
for spec in specs/active/*.md; do
  [ -f "$spec" ] || continue
  id=$(basename "$spec" .md | cut -d- -f1)
  pending=$(grep -c "spec:$id.*\[ \]" tasks/TASKS.md 2>/dev/null || echo 0)
  [ "$pending" = "0" ] && echo "$spec — 0 pending tasks"
done
```

```!
echo
echo "=== Merged local branches (candidates to prune) ==="
git branch --merged 2>/dev/null | grep -v '^\*' | grep -v ' main$' | grep -v ' master$' | head -10 || echo "(none)"
```

After running, **ask the user before**:
- Archiving any spec/plan
- Deleting any branch
- Truncating logs

Then perform the approved actions.
