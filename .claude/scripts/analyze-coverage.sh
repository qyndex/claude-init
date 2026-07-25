#!/usr/bin/env bash
# analyze-coverage.sh — spec:005 AC-2 (gap G2). The /analyze skill describes a
# spec→task coverage check but never RUNS it (zero .claude/state/analyze-*.json
# markers exist). This is the deterministic subset the skill can invoke:
#
#   bash .claude/scripts/analyze-coverage.sh <spec-id>          # write marker, exit 0
#   bash .claude/scripts/analyze-coverage.sh --check <spec-id>  # exit 1 if uncovered
#
# What it does:
#   - finds specs/{active,archive}/<id>-*.md, extracts every AC-N id from the
#     "## Acceptance criteria" section (only that section — an AC-9 in Goals is
#     not counted).
#   - parses tasks/TASKS.md for lines carrying spec:<id> (exact id, padded match),
#     counting how many reference the spec and how many are terminal-done ([x]/[s]).
#   - writes .claude/state/analyze-<id>.json (compact).
#
# HONEST SCOPE (documented, not aspirational): the task grammar has NO `ac:`
# field, so a *semantic* AC→task mapping (which task proves which AC) is out of
# scope here. This ships STRUCTURAL coverage: a spec is "structurally covered"
# when >=1 task references it. All ACs are enumerated in the marker so a human or
# the /analyze skill can map each AC to a task manually. UNCOVERED means the spec
# has ACs but zero tasks reference it at all.
#
# Test hooks: ANALYZE_SPECS_DIR (base dir searched for <id>-*.md, and its
# ../archive sibling), ANALYZE_TASKS, ANALYZE_STATE_DIR.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SPECS_DIR="${ANALYZE_SPECS_DIR:-specs/active}"
TASKS="${ANALYZE_TASKS:-tasks/TASKS.md}"
STATE_DIR="${ANALYZE_STATE_DIR:-.claude/state}"

CHECK=0
ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    -*) echo "analyze-coverage: unknown arg '$1'" >&2; exit 2 ;;
    *) ID="$1" ;;
  esac
  shift
done
[ -n "$ID" ] || { echo "usage: analyze-coverage.sh [--check] <spec-id>" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "analyze-coverage: jq required" >&2; exit 5; }

# Locate the spec file: active dir first, then a sibling archive dir.
spec=""
for cand in "$SPECS_DIR"/"$ID"-*.md "$(dirname "$SPECS_DIR")"/archive/"$ID"-*.md; do
  [ -f "$cand" ] && { spec="$cand"; break; }
done
[ -n "$spec" ] || { echo "analyze-coverage: no spec file for id $ID under $SPECS_DIR" >&2; exit 4; }

# Extract AC ids from the "## Acceptance criteria" section ONLY (up to the next
# "## " heading). sed prints the block; grep pulls AC-N; sort -u dedupes.
ac_block=$(sed -n '/^## Acceptance criteria/,/^## /p' "$spec")
acs=$(printf '%s\n' "$ac_block" | grep -oE 'AC-[0-9]+' | sort -u -V)
# jq array of AC ids (empty-safe: split drops the trailing blank line).
acs_json=$(printf '%s' "$acs" | jq -R -s 'split("\n") | map(select(length > 0))')
ac_total=$(printf '%s' "$acs_json" | jq 'length')

# Count tasks referencing spec:<id> (exact id, e.g. spec:005 not spec:0055).
# grep -c prints 0 AND exits 1 on no match → never `|| echo 0`; capture then guard.
tasks_for_spec=$(grep -cE "spec:${ID}([^0-9]|$)" "$TASKS" 2>/dev/null) || true
tasks_for_spec="${tasks_for_spec:-0}"
# Terminal-done task lines ([x] or [s]) that reference the spec.
tasks_done=$(grep -E "spec:${ID}([^0-9]|$)" "$TASKS" 2>/dev/null \
  | grep -cE '^- \[[xs]\]') || true
tasks_done="${tasks_done:-0}"

uncovered_note=""
if [ "$ac_total" -gt 0 ] && [ "$tasks_for_spec" -eq 0 ]; then
  uncovered_note="UNCOVERED: spec $ID has ACs but no tasks reference it"
fi

mkdir -p "$STATE_DIR"
MARK="$STATE_DIR/analyze-$ID.json"
generated=$(date -Iseconds 2>/dev/null || echo "")

jq -c -n \
  --arg spec "$ID" \
  --argjson ac_total "${ac_total:-0}" \
  --argjson acs "${acs_json:-[]}" \
  --argjson tasks_for_spec "${tasks_for_spec:-0}" \
  --argjson tasks_done "${tasks_done:-0}" \
  --arg uncovered_note "$uncovered_note" \
  --arg generated "$generated" \
  '{spec:$spec, ac_total:$ac_total, acs:$acs,
    tasks_for_spec:$tasks_for_spec, tasks_done:$tasks_done,
    uncovered_note:$uncovered_note, generated:$generated}' > "$MARK"

echo "analyze-coverage: spec $ID — ac_total=$ac_total tasks_for_spec=$tasks_for_spec tasks_done=$tasks_done → $MARK"
if [ -n "$uncovered_note" ]; then
  echo "$uncovered_note"
  [ "$CHECK" -eq 1 ] && exit 1
fi
exit 0
