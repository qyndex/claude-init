---
description: "Reconstruct the spec→plan→tasks→PRs→deploy 5-tuple for any commit. Compliance/audit use. Uses commit trailers (Spec: / Plan: / Task:) to walk the chain."
argument-hint: "<commit-sha-or-PR-number>"
allowed-tools: Read, Glob, Grep, Bash, WebFetch
disable-model-invocation: true
---

# /audit-trail — Compliance trace

```bash
target="$1"

# Resolve to commit SHA
if [[ "$target" =~ ^[0-9]+$ ]]; then
  # PR number → merge commit
  sha=$(gh pr view "$target" --json mergeCommit -q '.mergeCommit.oid')
else
  sha="$target"
fi

echo "# Audit trail for $sha"
echo

# 1. Commit details
echo "## Commit"
git log -1 --format='%H%n%an <%ae>%n%ad%n%s%n%n%b' "$sha"
echo

# 2. Extract trailers
echo "## Trailers"
spec_ref=$(git log -1 --format='%b' "$sha" | grep -E '^Spec:' | sed 's/Spec: //')
plan_ref=$(git log -1 --format='%b' "$sha" | grep -E '^Plan:' | sed 's/Plan: //')
task_ref=$(git log -1 --format='%b' "$sha" | grep -E '^Task:' | sed 's/Task: //')
constraint=$(git log -1 --format='%b' "$sha" | grep -E '^Constraint:' | sed 's/Constraint: //')
directive=$(git log -1 --format='%b' "$sha" | grep -E '^Directive:' | sed 's/Directive: //')
echo "- Spec: $spec_ref"
echo "- Plan: $plan_ref"
echo "- Task: $task_ref"
echo "- Constraint: $constraint"
echo "- Directive: $directive"
echo

# 3. Read the spec (active or archived)
if [ -n "$spec_ref" ]; then
  spec_file=$(ls $spec_ref 2>/dev/null || ls "${spec_ref/active/archive}" 2>/dev/null)
  if [ -n "$spec_file" ]; then
    echo "## Spec ($spec_file)"
    awk '/^---$/{c++;next} c==1' "$spec_file"  # just the frontmatter
    echo
    echo "Acceptance criteria:"
    awk '/^## Acceptance/,/^## /' "$spec_file" | tail -n +2
    echo
  fi
fi

# 4. Read the plan
if [ -n "$plan_ref" ]; then
  plan_file=$(ls $plan_ref 2>/dev/null || ls "${plan_ref/active/archive}" 2>/dev/null)
  if [ -n "$plan_file" ]; then
    echo "## Plan ($plan_file)"
    awk '/^---$/{c++;next} c==1' "$plan_file"
    echo
  fi
fi

# 5. PR details
echo "## PR details"
pr=$(gh pr list --state merged --search "$sha" --json number,title,reviews,statusCheckRollup --limit 1)
echo "$pr" | jq -r '.[0] | "- PR #\(.number): \(.title)\n- Reviews: \(.reviews | length)\n- Status checks: \(.statusCheckRollup | length)"'

# 6. CI status at merge
echo
echo "## CI checks at merge"
gh pr checks "$sha" 2>/dev/null

# 7. Deploy record (if release agent wrote one)
deploy_record=".claude/memory/deploys/$(date -d "$(git log -1 --format='%ai' "$sha")" '+%Y-%m' 2>/dev/null || echo "")"
if [ -d "$deploy_record" ]; then
  echo
  echo "## Deploy records this month"
  ls "$deploy_record"
fi

# 8. Related incidents
echo
echo "## Related incidents (mentioning this PR/spec)"
grep -rl "PR #${pr:-zzz}\|$spec_ref" .claude/memory/incidents/ 2>/dev/null
```

## Use cases

- **SOC2 audit**: "Show me the spec, code review, security review, and deploy chain for change X."
- **Customer-facing bug**: "What shipped at 14:00 on May 15?"
- **Postmortem**: "What was the chain of decisions that led to this incident?"
- **Spec-drift detection**: "Did the code that shipped actually implement spec 042's acceptance criteria?"

$ARGUMENTS
