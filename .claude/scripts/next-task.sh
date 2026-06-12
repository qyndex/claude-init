#!/usr/bin/env bash
# Canonical next-task picker (e2e-audit spec-pipeline-2 + tdd-loop-3).
#
# THE single task-nomination grammar. loop-iteration.sh, /implement next|all and
# workflow-state.sh all consume this instead of three divergent greps. Parses
# tasks/TASKS.md blocks below `## Active` only (the Format section's literal
# "T-NNN" template line can never match), requires a real T-<digits> id, skips
# operator-owned tasks (RESOLVE escalations), skips tasks whose deps are not all
# [x] (reported as blocked-by-dep), and orders by the priority taxonomy.
#
# Usage: next-task.sh [--all] [--json] [--why] [--require-analyze] [--require-approved]
#   (default)          print "T-NNN  <summary>" of the single nominated task
#   --all              print every eligible task in nomination order
#   --json             structured output {id, priority, spec, summary, blocked:[...]}
#   --why              also list skipped tasks with reasons (stderr in text mode)
#   --require-analyze  skip tasks whose spec lacks .claude/state/analyze-<id>.json
#                      with verdict != BLOCK (spec:HOTFIX exempt)
#   --require-approved skip tasks whose spec is not `status: approved` (HOTFIX exempt)
# Exit: 0 task nominated · 1 backlog empty (no pending tasks at all)
#       3 pending tasks exist but every one is blocked/skipped

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TASKS_FILE="${TASKS_FILE:-$ROOT/tasks/TASKS.md}"

ALL=0 JSON=0 WHY=0 REQ_ANALYZE=0 REQ_APPROVED=0
for arg in "$@"; do
  case "$arg" in
    --all) ALL=1 ;;
    --json) JSON=1 ;;
    --why) WHY=1 ;;
    --require-analyze) REQ_ANALYZE=1 ;;
    --require-approved) REQ_APPROVED=1 ;;
    *) echo "next-task.sh: unknown flag $arg" >&2; exit 64 ;;
  esac
done

[ -f "$TASKS_FILE" ] || { [ "$JSON" = 1 ] && echo '{"id":null,"reason":"no-tasks-file"}'; exit 1; }

# Completed ids — dep satisfaction checks against the whole file (archive incl.)
done_ids=$(grep -oE '^- \[x\] T-[0-9]+' "$TASKS_FILE" | grep -oE 'T-[0-9]+' | tr '\n' ' ')

# One awk pass over the Active section emits a TSV row per pending task block:
#   rank \t order \t id \t spec \t priority \t owner \t deps \t summary
candidates=$(awk -v done_ids=" $done_ids " '
  function rank(p) {
    if (p == "hotfix")            return 0
    if (p == "incident-followup") return 1
    if (p == "security")          return 2
    if (p == "P1-spec")           return 3
    if (p == "debt")              return 4
    if (p == "normal")            return 5
    if (p == "cleanup")           return 6
    if (p == "deprecation")       return 7
    return 8
  }
  # "-" placeholders prevent bash read from collapsing empty tab fields
  function nz(v) { return (v == "") ? "-" : v }
  function flush() {
    if (id == "") return
    printf "%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\n", rank(prio), order, id, nz(spec), nz(prio), nz(owner), nz(deps), nz(summary)
    id = ""
  }
  /^## Active/   { active = 1; next }
  !active        { next }
  # A new top-level entry of any status closes the open block
  /^- \[/ {
    flush()
    if ($0 ~ /^- \[ \] T-[0-9]+/) {
      order++
      match($0, /T-[0-9]+/); id = substr($0, RSTART, RLENGTH)
      spec = ""; if (match($0, /spec:[A-Za-z0-9-]+/)) spec = substr($0, RSTART+5, RLENGTH-5)
      prio = ""; if (match($0, /priority:[ ]*[A-Za-z0-9-]+/)) { prio = substr($0, RSTART, RLENGTH); sub(/priority:[ ]*/, "", prio) }
      deps = ""; if (match($0, /deps:[ ]*T-[0-9]+([ ]*,[ ]*T-[0-9]+)*/)) { deps = substr($0, RSTART, RLENGTH); sub(/deps:[ ]*/, "", deps); gsub(/[ ]/, "", deps) }
      owner = ""; summary = ""
    } else if ($0 ~ /^- \[ \]/) {
      # pending entry WITHOUT a real T-id (e.g. RESOLVE escalations) — operator-only
      order++
      printf "%d\t%d\tNON-ID\t-\t-\toperator\t-\t%s\n", 9, order, substr($0, 1, 80)
    }
    next
  }
  /^#/ { flush(); next }
  id != "" && /^[ \t]+summary:/ { s = $0; sub(/^[ \t]+summary:[ ]*/, "", s); summary = s }
  id != "" && /^[ \t]+owner:/   { o = $0; sub(/^[ \t]+owner:[ ]*/, "", o); owner = o }
  END { flush() }
' "$TASKS_FILE")

if [ -z "$candidates" ]; then
  [ "$JSON" = 1 ] && echo '{"id":null,"reason":"backlog-empty"}' || echo "no pending tasks"
  exit 1
fi

eligible="" blocked=""
while IFS=$'\t' read -r rnk order id spec prio owner deps summary; do
  # strip the awk "-" empty-field placeholders
  [ "$spec" = "-" ] && spec=""
  [ "$prio" = "-" ] && prio=""
  [ "$owner" = "-" ] && owner=""
  [ "$deps" = "-" ] && deps=""
  [ "$summary" = "-" ] && summary=""
  reason=""
  if [ "$id" = "NON-ID" ] || printf '%s' "$owner" | grep -qiE '^@?operator'; then
    reason="operator-owned"
  fi
  if [ -z "$reason" ] && [ -n "$deps" ]; then
    for dep in ${deps//,/ }; do
      case " $done_ids " in *" $dep "*) ;; *) reason="blocked-by-dep:$dep"; break ;; esac
    done
  fi
  if [ -z "$reason" ] && [ "$REQ_ANALYZE" = 1 ] && [ -n "$spec" ] && [ "$spec" != "HOTFIX" ]; then
    marker="$ROOT/.claude/state/analyze-${spec}.json"
    if [ ! -f "$marker" ]; then
      reason="analyze-marker-missing:$spec"
    elif [ "$(jq -r '.verdict // empty' "$marker" 2>/dev/null)" = "BLOCK" ]; then
      reason="analyze-verdict-block:$spec"
    fi
  fi
  if [ -z "$reason" ] && [ "$REQ_APPROVED" = 1 ] && [ -n "$spec" ] && [ "$spec" != "HOTFIX" ]; then
    # JUSTIFIED: glob may match nothing — a missing spec file is itself the skip reason
    spec_file=$(ls "$ROOT"/specs/active/"${spec}"-*.md 2>/dev/null | head -1)
    if [ -z "$spec_file" ] || ! grep -q '^status: *approved' "$spec_file" 2>/dev/null; then
      reason="spec-not-approved:$spec"
    fi
  fi
  if [ -n "$reason" ]; then
    blocked="${blocked}${id}\t${reason}\n"
  else
    eligible="${eligible}${rnk}\t${order}\t${id}\t${prio}\t${spec}\t${summary}\n"
  fi
done <<< "$candidates"

emit_blocked_json() { printf '%b' "$blocked" | jq -R -s 'split("\n") | map(select(length>0) | split("\t") | {id: .[0], reason: .[1]})'; }

if [ -z "$eligible" ]; then
  if [ "$JSON" = 1 ]; then
    jq -n --argjson blocked "$(emit_blocked_json)" '{id: null, reason: "all-blocked", blocked: $blocked}'
  else
    echo "pending tasks exist but none is eligible:"
    printf '%b' "$blocked" | sed 's/^/  /'
  fi
  exit 3
fi

picked=$(printf '%b' "$eligible" | sort -t$'\t' -k1,1n -k2,2n)
if [ "$ALL" = 0 ]; then picked=$(printf '%s\n' "$picked" | head -1); fi

if [ "$JSON" = 1 ]; then
  printf '%s\n' "$picked" | jq -R -s --argjson blocked "$(emit_blocked_json)" '
    (split("\n") | map(select(length>0) | split("\t") | {id: .[2], priority: .[3], spec: .[4], summary: .[5]})) as $picks
    | if ($picks | length) == 1 then $picks[0] + {blocked: $blocked} else {tasks: $picks, blocked: $blocked} end'
else
  printf '%s\n' "$picked" | awk -F'\t' '{ printf "%s  %s\n", $3, $6 }'
  if [ "$WHY" = 1 ] && [ -n "$blocked" ]; then
    printf 'skipped:\n%b' "$blocked" | sed 's/^T/  T/;s/^NON/  NON/' >&2
  fi
fi
exit 0
