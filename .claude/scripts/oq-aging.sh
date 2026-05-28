#!/usr/bin/env bash
# oq-aging.sh — escalate silently-skipped open questions (Spec 001 AC-5).
#
# Scans specs/active/**/*.md for [OQ-N] items in specs older than 7 days and
# appends a P1-spec RESOLVE task to tasks/TASKS.md for each, with a back-link and
# a last_touched stamp. Idempotent: an OQ already escalated is skipped.
#
# An OQ counts as "aged" when the nearest preceding `created:` date (the OQ's own
# inline `created:` if present, else the spec's top-level `created:`) is >7 days
# old. Daily cron via .claude/routines/oq-aging.yml.
#
# Overridable for tests: SPECS_DIR (default specs/active), TASKS_FILE (default
# tasks/TASKS.md), OQ_AGE_DAYS (default 7).

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

SPECS_DIR="${SPECS_DIR:-$ROOT/specs/active}"
export TASKS_FILE="${TASKS_FILE:-$ROOT/tasks/TASKS.md}"
OQ_AGE_DAYS="${OQ_AGE_DAYS:-7}"

# shellcheck source=lib/tasks-lib.sh
. "$ROOT/.claude/scripts/lib/tasks-lib.sh"

today_epoch=$(date +%s)

# date_to_epoch <YYYY-MM-DD> — portable (BSD + GNU); prints epoch or empty.
date_to_epoch() {
  local d="$1"
  # JUSTIFIED: BSD/GNU date portability — BSD form tried first, GNU form is the fallback; the trailing no-op makes the helper print empty for an unparseable date, the documented contract callers check
  date -j -f %Y-%m-%d "$d" +%s 2>/dev/null || date -d "$d" +%s 2>/dev/null || true
}

now_iso() { date -Iseconds; }

[ -d "$SPECS_DIR" ] || exit 0

# Walk every spec markdown file.
while IFS= read -r spec; do
  [ -f "$spec" ] || continue
  # Spec id = the directory name under specs/active (e.g. 007-aged), else basename.
  rel="${spec#"$SPECS_DIR"/}"
  spec_id="${rel%%/*}"
  [ "$spec_id" = "$rel" ] && spec_id="$(basename "$spec" .md)"

  # Top-level created: date for the spec (fallback age source).
  spec_created=$(grep -m1 -E '^created:' "$spec" | sed -E 's/^created:[[:space:]]*//' | tr -d '[:space:]')

  # Find each [OQ-N] line.
  while IFS= read -r line; do
    oq=$(printf '%s' "$line" | grep -oE 'OQ-[0-9]+' | head -1)
    [ -n "$oq" ] || continue

    # Age source: the OQ's own inline created:, else the spec's.
    oq_created=$(printf '%s' "$line" | grep -oE 'created:[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
    src_date="${oq_created:-$spec_created}"
    [ -n "$src_date" ] || continue

    src_epoch=$(date_to_epoch "$src_date")
    [ -n "$src_epoch" ] || continue
    age_days=$(( (today_epoch - src_epoch) / 86400 ))
    [ "$age_days" -gt "$OQ_AGE_DAYS" ] || continue

    # Idempotency: skip if a RESOLVE task for this spec+OQ already exists.
    # JUSTIFIED: presence probe — the redirect tolerates a missing TASKS_FILE on a fresh repo; absence correctly means "not yet escalated" so we proceed to append
    if grep -qE "RESOLVE: .*${spec_id}.* ${oq}\b" "$TASKS_FILE" 2>/dev/null; then
      continue
    fi

    iso="$(now_iso)"
    entry="- [ ] RESOLVE: specs/active/${spec_id} open question ${oq} | priority: P1-spec | created: $(date +%Y-%m-%d) | last_touched: ${iso}
      summary: Open question ${oq} in specs/active/${spec_id} has been open ${age_days}d (>${OQ_AGE_DAYS}d); escalated for operator triage
      spec: specs/active/${spec_id}/spec.md
      owner: operator"

    _append() { tasks_append_active "$entry"; }
    with_tasks_lock _append
    # JUSTIFIED: grep feed over the spec — the redirect guards a file removed mid-walk; no OQ lines means the inner loop simply does not iterate
  done < <(grep -nE '\[OQ-[0-9]+' "$spec" 2>/dev/null)
  # JUSTIFIED: find feed — the redirect tolerates a missing SPECS_DIR (already guarded by [ -d ] above); an empty result means no specs to scan
done < <(find "$SPECS_DIR" -type f -name '*.md' 2>/dev/null)

exit 0
