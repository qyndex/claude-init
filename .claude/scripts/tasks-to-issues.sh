#!/usr/bin/env bash
# Spec → GitHub Issue projector — Round 11 B.
#
# WRITE-ONLY projection. TASKS.md is the sole source of truth for task state;
# this script PUSHES spec state to GitHub Issues. It NEVER reads task state back
# from GitHub (that would invert authority — see no-issue-authority.yml CI guard).
#
# Grain: one issue per SPEC. Phases of L/XL specs become sub-issues. Atomic tasks
# render as a checklist inside the spec issue body (regenerated whole, idempotent).
#
# Usage:
#   bash .claude/scripts/tasks-to-issues.sh <spec-id>     # project one spec
#   bash .claude/scripts/tasks-to-issues.sh --all         # backfill every active spec
#   bash .claude/scripts/tasks-to-issues.sh <spec-id> --dry-run
#
# Requires: gh CLI authed with `project` scope. Honors GH secondary rate limits.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

target="${1:-}"
DRY_RUN=0
THROTTLE=0
for a in "$@"; do
  [ "$a" = "--dry-run" ] && DRY_RUN=1
  [ "$a" = "--throttle" ] && THROTTLE=1
done

[ -z "$target" ] && { echo "Usage: tasks-to-issues.sh <spec-id|--all> [--dry-run] [--throttle]"; exit 1; }

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found — projector requires it"; exit 1
fi

# Round 12 C: HOTFIX sentinel — project the lone ledger task(s) tagged spec:HOTFIX
# as type:hotfix issues (a hotfix has no originating spec file).
if [ "$target" = "HOTFIX" ]; then
  # Find hotfix tasks in TASKS.md without a hotfix_issue yet, create write-only issues
  # JUSTIFIED: awk over TASKS.md — the redirect tolerates a missing ledger file; no HOTFIX-tagged tasks means the while loop simply does not iterate
  awk '/^- \[/{t=$0} /spec:HOTFIX/{print t}' tasks/TASKS.md 2>/dev/null | while IFS= read -r task_line; do
    tid=$(echo "$task_line" | grep -oE 'T-[0-9]+')
    # summary is the next line after the task marker
    summary=$(grep -A1 "$tid" tasks/TASKS.md | grep 'summary:' | head -1 | sed 's/.*summary:[[:space:]]*//')
    fp=$(grep -A8 "$tid" tasks/TASKS.md | grep 'fingerprint:' | head -1 | sed 's/.*fingerprint:[[:space:]]*//')
    # Skip if already projected
    if grep -A8 "$tid" tasks/TASKS.md | grep -q 'hotfix_issue: #'; then continue; fi
    if [ "$DRY_RUN" = "1" ]; then echo "[dry-run] would create hotfix issue for $tid ($summary)"; continue; fi
    # JUSTIFIED: the redirect hides gh stderr; an empty url on failure yields an empty num that the `[ -n "$num" ]` guard below catches, so the loop just moves on
    url=$(gh issue create --title "[hotfix] $summary" \
      --body "Auto-projected hotfix for ledger task $tid (fingerprint $fp). Source of truth: tasks/TASKS.md. Enters board at DOING." \
      --label "type:hotfix,status:doing,priority:hotfix" 2>/dev/null)
    num=$(echo "$url" | grep -oE '[0-9]+$')
    if [ -n "$num" ]; then
      # JUSTIFIED: gh repo lookup — the redirect tolerates an unconfigured remote; an empty repo just skips the optional type PATCH below
      repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
      # JUSTIFIED: setting the hotfix issue type is best-effort cosmetic metadata; the fallback keeps a repo without issue-types configured from aborting the projection
      gh api "repos/${repo}/issues/${num}" -X PATCH -f type='Bug' >/dev/null 2>&1 || true
      # Write the issue number back into the task block (write-only)
      sed -i.bak "/$tid/,/hotfix_issue:/ s|hotfix_issue: <set by tasks-to-issues.sh projector>|hotfix_issue: #${num}|" tasks/TASKS.md && rm -f tasks/TASKS.md.bak
      echo "  ✓ hotfix issue #$num for $tid"
    fi
  done
  exit 0
fi

# Resolve spec list
specs=()
if [ "$target" = "--all" ]; then
  for s in specs/active/*.md; do [ -f "$s" ] && specs+=("$s"); done
else
  for s in specs/active/${target}*.md; do [ -f "$s" ] && specs+=("$s"); done
fi
[ "${#specs[@]}" -eq 0 ] && { echo "No matching specs"; exit 1; }

# Helper: extract a frontmatter field
fm() { awk -v k="$2" '/^---$/{c++; next} c==1 && $0 ~ "^"k":"{sub("^"k":[[:space:]]*",""); gsub(/"/,""); print; exit}' "$1"; }

project_one() {
  local spec="$1"
  local spec_id slug status title issue_num
  spec_id=$(basename "$spec" .md | grep -oE '^[0-9]+' | head -1)
  slug=$(basename "$spec" .md)
  status=$(fm "$spec" status)
  issue_num=$(fm "$spec" github_issue)

  # Build the checklist from TASKS.md tasks for this spec
  local checklist
  checklist=$(awk -v sid="$spec_id" '
    /^- \[/ {
      line=$0
      # Match tasks referencing this spec
      if (line ~ ("spec:" sid)) {
        mark="[ ]"
        if (line ~ /^- \[x\]/) mark="[x]"
        else if (line ~ /^- \[~\]/) mark="[~] (in progress)"
        else if (line ~ /^- \[!\]/) mark="[!] (failed)"
        else if (line ~ /^- \[b\]/) mark="[b] (blocked)"
        # extract task id
        tid=line; sub(/.*\(T-/,"T-",tid); sub(/[^0-9].*/,"",tid)
        match(line, /T-[0-9]+/); tid=substr(line, RSTART, RLENGTH)
        # next line is summary
        getline sumline
        sub(/^[[:space:]]*summary:[[:space:]]*/,"",sumline)
        checked=(mark=="[x]") ? "x" : " "
        printf "- [%s] %s — %s\n", checked, tid, sumline
      }
    }
  # JUSTIFIED: awk over TASKS.md — 2>/dev/null tolerates a missing file; an empty checklist is handled by the placeholder default on the next line
  ' tasks/TASKS.md 2>/dev/null)
  [ -z "$checklist" ] && checklist="_(no tasks projected yet — planner has not decomposed this spec)_"

  # Count for lifecycle hint
  local total done_count
  # JUSTIFIED: grep -c counting checklist rows; grep exits 1 on zero matches, so `|| echo 0` defaults the count for an empty checklist (value only feeds a display string)
  total=$(echo "$checklist" | grep -c '^- \[' || echo 0)
  # JUSTIFIED: grep -c counting completed rows; `|| echo 0` defaults the count when no task is done yet (display-only "$done / $total")
  done_count=$(echo "$checklist" | grep -c '^- \[x\]' || echo 0)

  # Body (regenerated WHOLE — idempotent)
  local body
  body=$(cat <<EOF
> **Auto-projected from \`$spec\` by tasks-to-issues.sh — do not hand-edit the checklist.**
> TASKS.md is the source of truth. Human edits here are advisory; the next sync overwrites.

**Spec:** \`$spec\`
**Status:** $status
**Tasks:** $done_count / $total complete

## Task checklist (projected from tasks/TASKS.md)

$checklist

---
🤖 Projected by the factory. Lifecycle: TODO→DOING→DONE→SHIPPED on the project board.
EOF
)

  title="[feat] $slug"

  if [ "$DRY_RUN" = "1" ]; then
    echo "── DRY RUN: spec $spec_id ──"
    echo "title: $title"
    echo "issue: ${issue_num:-<would create>}"
    echo "$body" | head -12
    echo
    return
  fi

  if [ -n "$issue_num" ]; then
    # Update existing — write-only, regenerate body
    gh issue edit "$issue_num" --body "$body" >/dev/null 2>&1 \
      && echo "  ✓ updated issue #$issue_num ($slug)" \
      || echo "  ✗ failed to update #$issue_num"
  else
    # Create new — set type via gh api (gh issue create has no --type)
    # JUSTIFIED: 2>/dev/null hides gh's stderr; the empty new_url on failure is detected by the `[ -n "$new_num" ]` guard below, which reports the failure explicitly
    new_url=$(gh issue create --title "$title" --body "$body" --label "type:feature,status:todo" 2>/dev/null)
    new_num=$(echo "$new_url" | grep -oE '[0-9]+$')
    if [ -n "$new_num" ]; then
      # Set the issue type (Feature) via REST
      # JUSTIFIED: gh repo lookup — 2>/dev/null tolerates a detached/unconfigured remote; an empty repo just skips the optional type PATCH below
      repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
      # JUSTIFIED: setting issue type is best-effort cosmetic metadata; `|| true` + 2>&1 keep a repo without issue-types configured from failing the projection
      gh api "repos/${repo}/issues/${new_num}" -X PATCH -f type='Feature' >/dev/null 2>&1 || true
      # Store the issue number back into the spec frontmatter
      if grep -q '^github_issue:' "$spec"; then
        sed -i.bak "s|^github_issue:.*|github_issue: $new_num|" "$spec" && rm -f "${spec}.bak"
      else
        # insert after status line
        sed -i.bak "/^status:/a\\
github_issue: $new_num
" "$spec" && rm -f "${spec}.bak"
      fi
      echo "  ✓ created issue #$new_num ($slug) + stored in spec frontmatter"
    else
      echo "  ✗ failed to create issue for $slug"
    fi
  fi

  # Rate-limit courtesy
  [ "$THROTTLE" = "1" ] && sleep 2
}

echo "→ Projecting ${#specs[@]} spec(s) to GitHub Issues (write-only)"
for spec in "${specs[@]}"; do
  project_one "$spec"
done
echo "Done. Board lifecycle is driven by .github/workflows/issue-lifecycle.yml on PR/deploy events."
