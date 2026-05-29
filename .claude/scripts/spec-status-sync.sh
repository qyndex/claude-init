#!/usr/bin/env bash
# spec-status-sync.sh — advance a spec's frontmatter status: approved → shipped
# once every task referencing it in tasks/TASKS.md is done ([x]) or skipped ([s]).
# Spec 003 AC-16. Mirrors how post-write-roadmap.sh already derives state from
# TASKS.md; called from that hook when TASKS.md changes.
#
# A spec qualifies when, for spec id NNN:
#   - at least one task line contains "spec:NNN", AND
#   - every such task line is "[x]" or "[s]" (none pending/in-progress/blocked/failed).
# Then its specs/active/NNN-*.md frontmatter "status: approved" is rewritten to
# "status: shipped" and "updated:" bumped to TODAY.
#
# --dry-run lists what would change without writing. Exit 0 always (advisory).
#
# Overridable for tests: SPECS_DIR, TASKS_FILE, TODAY.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

SPECS_DIR="${SPECS_DIR:-$ROOT/specs/active}"
TASKS_FILE="${TASKS_FILE:-$ROOT/tasks/TASKS.md}"
# JUSTIFIED: date is unavailable to the model in some contexts; allow TODAY override for deterministic tests
TODAY="${TODAY:-$(date -u +%Y-%m-%d 2>/dev/null || echo 0000-00-00)}"

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

[ -d "$SPECS_DIR" ] || { echo "spec-status-sync: no specs dir ($SPECS_DIR)"; exit 0; }
[ -f "$TASKS_FILE" ] || { echo "spec-status-sync: no tasks file ($TASKS_FILE)"; exit 0; }

changed=0
for spec in "$SPECS_DIR"/*.md; do
  [ -f "$spec" ] || continue
  base="$(basename "$spec")"
  # Spec id = leading digits of the filename (e.g. 002-audit... → 002).
  id="${base%%-*}"
  case "$id" in ''|*[!0-9]*) continue ;; esac   # skip non-numeric (e.g. .gitkeep)

  # Only act on approved specs.
  grep -qE '^status:[[:space:]]*approved[[:space:]]*$' "$spec" || continue

  # Gather task lines referencing this spec.
  total=$(grep -cE "spec:${id}([^0-9]|$)" "$TASKS_FILE" 2>/dev/null || echo 0)
  [ "$total" -gt 0 ] || continue   # no referencing tasks → nothing to conclude

  # Count tasks that are NOT done/skipped (pending, in-progress, blocked, failed).
  open=$(grep -E "spec:${id}([^0-9]|$)" "$TASKS_FILE" \
         | grep -cE '^\- \[( |~|!|b)\]' || true)
  [ "$open" -eq 0 ] || continue    # still has open work → keep approved

  if [ "$dry_run" = "1" ]; then
    echo "would ship: $base ($total tasks, all done)"
    changed=$((changed + 1))
    continue
  fi

  # Rewrite status + updated. Surgical: only the two frontmatter lines.
  tmp="$(mktemp)"
  awk -v today="$TODAY" '
    BEGIN { infm=0; seen=0 }
    /^---[[:space:]]*$/ { seen++; print; if (seen==1) infm=1; else infm=0; next }
    infm && /^status:[[:space:]]*approved[[:space:]]*$/ { print "status: shipped"; next }
    infm && /^updated:/ { print "updated: " today; next }
    { print }
  ' "$spec" > "$tmp" && mv "$tmp" "$spec"
  echo "shipped: $base ($total tasks, all done)"
  changed=$((changed + 1))
done

[ "$changed" -eq 0 ] && echo "spec-status-sync: no specs to advance"
exit 0
