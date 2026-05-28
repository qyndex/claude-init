#!/usr/bin/env bash
# Brownfield adoption state machine — Round 14.
#
# The `/adopt` flow is SIX human-gated phases that must run in order and cannot be
# skipped. This script is the single reader/writer of the adoption state file so the
# phase contract stays consistent. State lives at .claude/state/adopt/STATE.json and is
# COMMITTED (durable adoption state, unlike runtime locks) so the contract survives across
# sessions/machines and a half-finished adoption can't be silently forgotten.
#
# Phases:  0 none → 1 archaeology → 2 reconcile → 3 import → 4 baseline → 5 backlog → 6 handoff(done)
# Each phase writes its outputs, then sets status=awaiting-approval and STOPS. A human runs
# `/adopt approve <n>`; the NEXT phase calls `gate <n>` and refuses to start until approved.
#
# Usage:
#   adopt-state.sh init [repo-path]      # create STATE.json at phase 0
#   adopt-state.sh show                  # print STATE.json
#   adopt-state.sh phase                 # print current phase number
#   adopt-state.sh status                # print current status string
#   adopt-state.sh set <n> <name>        # advance to phase <n>, status=awaiting-approval
#   adopt-state.sh approve <n>           # record human approval of phase <n>
#   adopt-state.sh gate <n>              # exit 0 if phase <n> approved, else exit 1
#   adopt-state.sh complete              # mark adoption done

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"

command -v jq >/dev/null 2>&1 || { echo "adopt-state: jq required"; exit 1; }

STATE_DIR=".claude/state/adopt"
STATE="$STATE_DIR/STATE.json"

phase_name() { case "$1" in
  0) echo "none" ;; 1) echo "archaeology" ;; 2) echo "reconcile" ;;
  3) echo "import" ;; 4) echo "baseline" ;; 5) echo "backlog" ;; 6) echo "handoff" ;;
  *) echo "unknown" ;; esac; }

# JUSTIFIED: shift with no positional args errors on some shells; the redirect and fallback keep the script running when invoked with only a subcommand and no further args
cmd="${1:-show}"; shift 2>/dev/null || true

case "$cmd" in
  init)
    mkdir -p "$STATE_DIR"
    repo="${1:-$ROOT}"
    # JUSTIFIED: the redirect drops jq stderr on a malformed STATE.json — a non-"complete" result (including empty) correctly treats an unreadable state as an in-progress adoption and aborts
    if [ -f "$STATE" ] && [ "$(jq -r '.status' "$STATE" 2>/dev/null)" != "complete" ]; then
      echo "adopt-state: an adoption is already in progress (phase $(jq -r .phase "$STATE")). 'show' to inspect."; exit 1
    fi
    jq -n --arg repo "$repo" --arg now "$(date -Iseconds)" \
      '{repo:$repo, started_at:$now, phase:0, phase_name:"none", status:"initialized", approvals:{}}' > "$STATE"
    echo "✓ adoption initialized for $repo (phase 0)"
    ;;
  show)    [ -f "$STATE" ] && cat "$STATE" || { echo "no adoption in progress (.claude/state/adopt/STATE.json absent)"; exit 1; } ;;
  # JUSTIFIED: the fallback prints phase 0 when no state file exists — the documented sentinel for "no adoption started", so callers parsing the phase number get a valid value
  phase)   [ -f "$STATE" ] && jq -r '.phase' "$STATE" || echo 0 ;;
  status)  [ -f "$STATE" ] && jq -r '.status' "$STATE" || echo "none" ;;
  set)
    [ -f "$STATE" ] || { echo "adopt-state: run 'init' first"; exit 1; }
    n="${1:?phase number}"; nm="$(phase_name "$n")"
    tmp="$STATE.tmp.$$"
    jq --argjson n "$n" --arg nm "$nm" --arg now "$(date -Iseconds)" \
      '.phase=$n | .phase_name=$nm | .status="awaiting-approval" | .updated_at=$now' "$STATE" > "$tmp" && mv "$tmp" "$STATE"
    echo "✓ phase $n ($nm) complete — awaiting human approval (run: /adopt approve $n)"
    ;;
  approve)
    [ -f "$STATE" ] || { echo "adopt-state: no adoption in progress"; exit 1; }
    n="${1:?phase number}"
    cur="$(jq -r '.phase' "$STATE")"
    [ "$n" -le "$cur" ] || { echo "adopt-state: cannot approve phase $n — current phase is $cur"; exit 1; }
    tmp="$STATE.tmp.$$"
    jq --arg n "$n" --arg now "$(date -Iseconds)" \
      '.approvals[$n]=$now | .status=("approved-"+$n)' "$STATE" > "$tmp" && mv "$tmp" "$STATE"
    echo "✓ phase $n approved at $(date -Iseconds). You may run the next phase."
    ;;
  gate)
    [ -f "$STATE" ] || { echo "adopt-state: no adoption in progress — run /adopt start first"; exit 1; }
    n="${1:?required phase}"
    if [ "$(jq -r --arg n "$n" '.approvals[$n] // ""' "$STATE")" = "" ]; then
      echo "adopt-state: phase $n ($(phase_name "$n")) is not approved yet — run '/adopt approve $n' first"; exit 1
    fi
    ;;
  complete)
    [ -f "$STATE" ] || { echo "adopt-state: no adoption in progress"; exit 1; }
    tmp="$STATE.tmp.$$"
    jq --arg now "$(date -Iseconds)" '.phase=6 | .phase_name="handoff" | .status="complete" | .completed_at=$now' "$STATE" > "$tmp" && mv "$tmp" "$STATE"
    echo "✓ adoption complete — repo now uses the standard 8-phase workflow"
    ;;
  *) echo "Usage: adopt-state.sh {init|show|phase|status|set <n> <name>|approve <n>|gate <n>|complete}"; exit 1 ;;
esac
