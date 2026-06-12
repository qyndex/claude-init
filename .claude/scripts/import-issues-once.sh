#!/usr/bin/env bash
# ONE-TIME BROWNFIELD MIGRATION — NOT an ongoing state read. Round 14.
# This script runs EXACTLY ONCE at adoption (Phase 3) to seed the backlog from the brownfield
# repo's existing GitHub Issues. It reads issue state ONLY to populate tasks/TASKS.md (open →
# pending tasks) and .claude/memory/ (closed → history); thereafter tasks/TASKS.md is the SOLE
# source of truth (CLAUDE.md §XVII) and this script self-terminates via the
# .claude/state/adopt/issues-imported.done sentinel. Going forward, issue traffic is WRITE-ONLY
# via tasks-to-issues.sh. Do NOT call this from any routine, hook, skill, or inner loop — it is
# a migration, not a sync. (Allowlisted in check-no-issue-authority.sh by exact basename.)
#
# Imported tasks carry `imported_from_issue: #N` and NO `github_issue:` — disjoint from the
# projector's key, so they are never re-projected back as new issues (no loop, no inversion).
#
# Usage:  import-issues-once.sh [--limit N] [--dry-run]

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
. "$ROOT/.claude/scripts/lib/tasks-lib.sh"

LIMIT=500; DRY=0
while [ $# -gt 0 ]; do case "$1" in
  --limit) LIMIT="${2:-500}"; shift 2 ;; --dry-run) DRY=1; shift ;; *) shift ;;
esac; done

SENTINEL=".claude/state/adopt/issues-imported.done"
mkdir -p .claude/state/adopt .claude/memory

# ── Self-terminate: this migration runs once, ever ───────────────────────
if [ -f "$SENTINEL" ]; then
  echo "Issues already imported $(cat "$SENTINEL"). This is a ONE-TIME migration; re-running is forbidden."
  echo "For ongoing issue sync use tasks-to-issues.sh (write-only). Delete $SENTINEL only to deliberately re-migrate."
  exit 1
fi
command -v gh >/dev/null 2>&1 || { echo "import-issues-once: gh CLI required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "import-issues-once: jq required"; exit 1; }
# e2e-audit brownfield-5: an unauthenticated gh must be a loud refusal up-front —
# a fail-silent zero-import would write the permanent sentinel and sever the backlog.
if ! gh auth status >/dev/null 2>&1; then
  echo "import-issues-once: ERROR — 'gh auth status' failed (not authenticated?)." >&2
  echo "NOT importing, NOT writing the sentinel. Run 'gh auth login', then re-run." >&2
  exit 1
fi
[ -f tasks/TASKS.md ] || printf '# Tasks\n\n## Active\n\n## Archive\n' > tasks/TASKS.md

now="$(date -Iseconds)"

# ── OPEN issues → pending tasks (under the TASKS.md lock) ─────────────────
# brownfield-5: a failed read must be distinguishable from "zero open issues" —
# error out WITHOUT the sentinel so the migration stays re-runnable.
gh_err="$(mktemp)"
if ! open_json="$(gh issue list --state open --json number,title,labels --limit "$LIMIT" 2>"$gh_err")"; then
  echo "import-issues-once: ERROR — 'gh issue list --state open' failed:" >&2
  cat "$gh_err" >&2; rm -f "$gh_err"
  echo "NOT writing the sentinel — the backlog was NOT read. Fix gh (auth/network/rate-limit) and re-run." >&2
  exit 1
fi
open_count="$(echo "$open_json" | jq 'length')"
imported_open=0

_import_open() {
  local next_id num title labels entry
  next_id="$(tasks_next_id)"
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    num="$(echo "$row" | jq -r '.number')"
    title="$(echo "$row" | jq -r '.title' | head -c 180)"
    # JUSTIFIED: jq error muted — an issue with no labels array yields empty labels, which the conditional in the printf below treats as "omit labels line"
    labels="$(echo "$row" | jq -r '[.labels[].name] | join(",")' 2>/dev/null)"
    # dedup: skip if this issue was already imported
    # JUSTIFIED: grep error muted — an absent tasks/TASKS.md (first-ever import) is a non-match, so the issue is correctly imported rather than skipped
    grep -q "imported_from_issue: #${num}\b" tasks/TASKS.md 2>/dev/null && continue
    entry=$(printf -- '- [ ] T-%s  | priority: normal  | created: %s  | last_touched: %s\n  summary: %s\n  files: <tbd>\n  accept: <human decision required — triage this imported issue>\n  owner: @unassigned\n  source: github-issue-#%s\n  imported_from_issue: #%s%s' \
      "$next_id" "$now" "$now" "$title" "$num" "$num" "$([ -n "$labels" ] && printf '\n  labels: %s' "$labels")")
    tasks_append_active "$entry"
    next_id=$((next_id + 1)); imported_open=$((imported_open + 1))
  done < <(echo "$open_json" | jq -c '.[]')
}

if [ "$DRY" = 1 ]; then
  echo "[dry-run] would import $open_count open issue(s) as pending tasks"
else
  with_tasks_lock _import_open
  [ "$?" -eq 75 ] && { echo "import-issues-once: TASKS.md lock busy — retry"; exit 75; }
fi

# ── CLOSED issues → memory history (NOT tasks) ───────────────────────────
HIST=".claude/memory/imported-issues-closed.md"
# brownfield-5: same loud-failure contract as the open read. Open imports already
# appended above are safe — the imported_from_issue dedup makes a re-run idempotent.
if ! closed_json="$(gh issue list --state closed --json number,title,closedAt --limit "$LIMIT" 2>"$gh_err")"; then
  echo "import-issues-once: ERROR — 'gh issue list --state closed' failed:" >&2
  cat "$gh_err" >&2; rm -f "$gh_err"
  echo "NOT writing the sentinel — re-run after fixing gh (open-issue imports are deduped on re-run)." >&2
  exit 1
fi
rm -f "$gh_err"
closed_count="$(echo "$closed_json" | jq 'length')"
if [ "$DRY" = 1 ]; then
  echo "[dry-run] would write $closed_count closed issue(s) to $HIST (history, not backlog)"
else
  {
    printf '# Imported closed issues (history) — %s\n\n' "$now"
    printf 'Closed issues from the brownfield repo, imported once at adoption as HISTORY (not backlog).\n\n'
    echo "$closed_json" | jq -r '.[] | "- #\(.number) \(.title) (closed \(.closedAt // "?"))"'
  } > "$HIST"
  # JUSTIFIED: best-effort memory reindex — the closed-issue history file is already written; a reindex failure must not abort the migration or block sentinel creation
  [ -f .claude/scripts/memory-index.sh ] && bash .claude/scripts/memory-index.sh backfill >/dev/null 2>&1 || true
fi

# ── Write the self-terminating sentinel (COMMIT it — it must survive) ─────
if [ "$DRY" = 0 ]; then
  printf '%s — imported %s open → tasks, %s closed → history\n' "$now" "${imported_open:-0}" "$closed_count" > "$SENTINEL"
  echo "✓ Imported ${imported_open:-0} open issue(s) → tasks/TASKS.md, $closed_count closed → $HIST"
  echo "  Sentinel written: $SENTINEL (commit it). Future issue traffic is WRITE-ONLY via tasks-to-issues.sh."
  # JUSTIFIED: best-effort adoption-phase bump — the import + sentinel already succeeded; a phase-tracker failure must not undo a completed one-time migration
  [ -f .claude/scripts/adopt-state.sh ] && bash .claude/scripts/adopt-state.sh set 3 import >/dev/null 2>&1 || true
else
  echo "[dry-run] no sentinel written; no state change"
fi
