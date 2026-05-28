---
description: Project specs onto GitHub Issues (write-only) + inspect lifecycle. tasks/TASKS.md stays the source of truth; this pushes spec state to the board. Round 11.
argument-hint: "<sync [spec-id] | sync --all | status [spec-id] | setup-check>"
allowed-tools: Read, Glob, Grep, Bash
disable-model-invocation: true
---

# /issues — Spec → GitHub Issue projection

Write-only projection of specs onto GitHub Issues + a Projects v2 board. **Never reads task state back** (that authority stays with `tasks/TASKS.md`).

```bash
verb="${1:-status}"
shift 2>/dev/null

case "$verb" in
  sync)
    # Project one spec or all active specs
    if [ "${1:-}" = "--all" ]; then
      bash .claude/scripts/tasks-to-issues.sh --all --throttle
    elif [ -n "${1:-}" ]; then
      bash .claude/scripts/tasks-to-issues.sh "$1"
    else
      echo "Usage: /issues sync <spec-id> | /issues sync --all"
    fi
    ;;

  status)
    # Read-only board view — uses gh project, NOT task-state read from issues.
    # (Showing project Status column is fine; reading task [x]/[ ] back is forbidden.)
    echo "Spec → issue mapping (from spec frontmatter, the source of truth):"
    for spec in specs/active/*.md; do
      [ -f "$spec" ] || continue
      gh_issue=$(awk '/^github_issue:/{print $2}' "$spec")
      slug=$(basename "$spec" .md)
      st=$(awk '/^status:/{print $2; exit}' "$spec")
      printf "  %-40s spec-status=%-10s issue=%s\n" "$slug" "$st" "${gh_issue:-<not projected>}"
    done
    ;;

  setup-check)
    echo "Checking issue-projection setup..."
    echo -n "  gh CLI authed: "; gh auth status >/dev/null 2>&1 && echo yes || echo "NO — run gh auth login"
    echo -n "  project scope: "; gh auth status 2>&1 | grep -q 'project' && echo yes || echo "missing — gh auth refresh -s project"
    echo -n "  ISSUE_TEMPLATE forms: "; ls .github/ISSUE_TEMPLATE/*.yml >/dev/null 2>&1 && echo "$(ls .github/ISSUE_TEMPLATE/*.yml | wc -l | tr -d ' ') present" || echo "none"
    echo -n "  lifecycle workflow: "; [ -f .github/workflows/issue-lifecycle.yml ] && echo present || echo MISSING
    echo -n "  authority guard: "; [ -f .github/workflows/no-issue-authority.yml ] && echo present || echo MISSING
    echo
    echo "Remaining manual setup (per docs/ISSUE-LIFECYCLE.md):"
    echo "  - Create org issue types + Projects v2 board (TODO/DOING/DONE/SHIPPED)"
    echo "  - Set repo variables: PROJECT_ID, STATUS_FIELD_ID, STATUS_TODO/DOING/DONE/SHIPPED"
    echo "  - Replace OWNER/PROJECT_NUMBER in .github/ISSUE_TEMPLATE/*.yml"
    ;;

  *)
    echo "Usage: /issues sync [spec-id|--all] | status [spec-id] | setup-check"
    ;;
esac
```

## Hard rules

- **Write-only.** This command projects spec state TO GitHub. It must never read task `[x]`/`[ ]` state FROM GitHub. `no-issue-authority.yml` enforces.
- **Idempotent.** Re-running `sync` regenerates the full checklist; safe to run repeatedly.
- **Boundary-only.** Don't wire this into the autonomous inner loop — run at PR-time / merge / manually.

$ARGUMENTS
