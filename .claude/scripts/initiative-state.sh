#!/usr/bin/env bash
# initiative-state.sh — the living STATE.md per initiative + session pointers.
#
# Memory-system review (docs/research/memory-system-review.md §7.2): the
# initiative layer had no living state file and the .claude/state/current-*
# pointers were read by session-end.sh but never written by anything.
#
# Subcommands:
#   sync   Derive current initiative/spec, write pointer files, regenerate
#          initiatives/active/<base>.STATE.md (≤60 lines, machine-rewritten).
#          Call at network boundaries: session end, /ship, /verify, merges.
#   show   One-line summary of the newest STATE.md (for session-start injection).
#
# Failures are LOUD (stderr + non-zero exit) — memory-plane writes must not
# fail silently (review §7.6).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# M-10-lock: all memory-plane writers share ONE lock so a backgrounded dream's
# sync can't interleave with a live session's STATE.md write. Locked at per-spec
# write granularity (inside sync_one_spec) so a multi-spec sync loop doesn't hold
# the lock across the whole loop.
# shellcheck source=lib/with-lock.sh
. "$(dirname "$0")/lib/with-lock.sh"

STATE_DIR=".claude/state"
INIT_DIR="initiatives/active"

die() { echo "initiative-state: $*" >&2; exit 1; }

current_spec() {
  # Newest active spec, mirroring workflow-state.sh's derivation.
  # JUSTIFIED: no active spec is a valid early-workflow state — empty output, caller handles
  ls -t specs/active/*.md 2>/dev/null | head -1
}

current_initiative_file() {
  # Newest real initiative file (not a generated STATE file).
  # JUSTIFIED: empty initiatives/active is the common state in spec-level projects — empty output triggers the spec fallback
  ls -t "$INIT_DIR"/*.md 2>/dev/null | grep -v '\.STATE\.md$' | head -1
}

sync_one_spec() {
  mkdir -p "$STATE_DIR" "$INIT_DIR"

  local spec spec_base spec_id init_file init_base
  # M-07-state: the spec to sync is passed in (all-initiative sync), falling back
  # to the newest active spec for backward compatibility when called with no arg.
  spec="${1:-$(current_spec)}"
  spec_base=""
  spec_id=""
  if [ -n "$spec" ]; then
    spec_base=$(basename "$spec" .md)
    spec_id=$(printf '%s' "$spec_base" | grep -oE '^[0-9]+' || true)
  fi

  init_file=$(current_initiative_file)
  if [ -n "$init_file" ]; then
    init_base=$(basename "$init_file" .md)
  elif [ -n "$spec_base" ]; then
    # Spec-level project: the spec IS the initiative.
    init_base="spec-${spec_base}"
  else
    echo "initiative-state: no active spec or initiative — nothing to sync" >&2
    return 0
  fi

  # ── Pointer files (consumed by session-end.sh for token attribution) ──
  printf '%s' "$init_base" > "$STATE_DIR/current-initiative" \
    || die "failed writing $STATE_DIR/current-initiative"
  printf '%s' "${spec_base:-none}" > "$STATE_DIR/current-spec" \
    || die "failed writing $STATE_DIR/current-spec"

  # ── Gather state ──
  local phase plan tasks_total tasks_done tasks_prog tasks_blocked tasks_pending tasks_shipped
  # JUSTIFIED: no active plan is valid pre-planning state — "none" sentinel
  plan=$(ls -t plans/active/*.md 2>/dev/null | head -1 || echo none)

  count_tasks() { # status-char
    local pat="^- \[$1\] T-[0-9]+" c
    [ -n "$spec_id" ] && pat="${pat}.*spec:${spec_id}"
    # JUSTIFIED: grep -c prints 0 AND exits 1 on zero matches — capture then default, never `|| echo` (would double-print)
    c=$(grep -cE "$pat" tasks/TASKS.md 2>/dev/null) || true
    echo "${c:-0}"
  }
  tasks_done=$(count_tasks x)
  tasks_prog=$(count_tasks '~')
  tasks_blocked=$(count_tasks b)
  tasks_pending=$(count_tasks ' ')
  # M-07-state: count [s] shipped tasks too (spec-004's reconciled tasks are [s]).
  # Without this they vanish from the total and a fully-shipped spec looks empty.
  tasks_shipped=$(count_tasks s)
  tasks_total=$((tasks_done + tasks_prog + tasks_blocked + tasks_pending + tasks_shipped))

  # M-07-state: derive phase from GROUND TRUTH (this spec's task states), not the
  # global .swarms/coordinator/workflow-state.json — that stale swarm file made
  # STATE.md report the wrong phase (e.g. "specifying · 1/18" for a shipped spec).
  local terminal_done=$((tasks_done + tasks_shipped))
  if [ "$tasks_total" -eq 0 ]; then
    # No tasks for this spec yet — fall back to the workflow-state phase hint.
    # JUSTIFIED: missing/corrupt workflow-state.json degrades to "specifying" (pre-task default)
    phase=$(jq -r '.phase // "specifying"' .swarms/coordinator/workflow-state.json 2>/dev/null || echo specifying)
  elif [ "$terminal_done" -eq "$tasks_total" ]; then
    phase="shipped"
  elif [ "$tasks_prog" -gt 0 ]; then
    phase="implementing"
  elif [ "$terminal_done" -gt 0 ]; then
    phase="implementing"
  else
    phase="planned"
  fi

  local oq_count=""
  if [ -n "$spec" ]; then
    # JUSTIFIED: grep -c prints 0 AND exits 1 on zero matches — capture then default
    oq_count=$(grep -c '\[OQ' "$spec" 2>/dev/null) || true
  fi
  oq_count="${oq_count:-0}"

  local state_file="$INIT_DIR/${init_base}.STATE.md" ts
  ts=$(date -Iseconds)

  # M-10-lock: the two-command write (build .tmp, then head→final install) is not
  # atomic — a concurrent memory-plane writer could clobber it. Wrapped in the
  # shared lock at per-spec granularity so a multi-spec cmd_sync loop only holds
  # the lock for one spec's write, not the whole loop. Dynamic scoping keeps the
  # enclosing locals (spec, phase, tasks_*, etc.) visible to the nested writer.
  _write_state_file() {
  {
    echo "# STATE — ${init_base}"
    echo
    echo "> Machine-rewritten by \`.claude/scripts/initiative-state.sh sync\` at network"
    echo "> boundaries (session end, ship, verify, merge). Do not hand-edit; history"
    echo "> lives in git. This is the always-current answer to \"where is this initiative?\""
    echo
    echo "- **updated_at**: $ts"
    echo "- **phase**: $phase"
    echo "- **spec**: ${spec:-none}"
    echo "- **plan**: $plan"
    echo "- **tasks**: $((tasks_done + tasks_shipped))/${tasks_total} done · ${tasks_shipped} shipped · ${tasks_prog} in-progress · ${tasks_blocked} blocked · ${tasks_pending} pending"
    echo "- **open questions**: $oq_count"
    echo
    echo "## Next unblocked tasks"
    # T-[0-9]+ guard: never pick up the TASKS.md format-template line.
    # M-07-state: filter by THIS spec's id — previously the unfiltered grep listed
    # another spec's tasks as this spec's "next" (spec-003 tasks under spec-004).
    # JUSTIFIED: no pending tasks makes grep exit 1 — the placeholder line below covers it
    grep -m3 -E "^- \[ \] T-[0-9]+.*spec:${spec_id:-[0-9]+}" tasks/TASKS.md 2>/dev/null | sed 's/^- \[ \] */- /' || echo "_(none)_"
    echo
    echo "## Last 5 events (git)"
    # JUSTIFIED: empty repo makes log fail — empty section acceptable in the brief
    git log --oneline -5 2>/dev/null | sed 's/^/- /' || true
    echo
    echo "## Blockers"
    # M-07-state: spec-filtered, same reason as Next unblocked tasks above.
    # JUSTIFIED: no blocked tasks makes grep exit 1 — placeholder covers it
    grep -m5 -E "^- \[b\] T-[0-9]+.*spec:${spec_id:-[0-9]+}" tasks/TASKS.md 2>/dev/null | sed 's/^- \[b\] */- /' || echo "_(none)_"
  } > "${state_file}.tmp" || die "failed writing ${state_file}.tmp"

  head -n 60 "${state_file}.tmp" > "$state_file" && rm -f "${state_file}.tmp" \
    || die "failed installing $state_file"
  }
  with_lock "memory-plane" _write_state_file

  echo "initiative-state: synced $state_file (phase=$phase tasks=$((tasks_done + tasks_shipped))/${tasks_total})"
}

cmd_sync() {
  # M-07-state: sync ALL active specs, not just the newest-by-mtime. Previously
  # only current_spec (ls -t | head -1) was synced, so a second active spec's
  # STATE.md silently rotted. Loop every specs/active/*.md; if none, sync once
  # with no spec (initiative-only / pre-spec project).
  local synced=0 s
  for s in specs/active/*.md; do
    [ -f "$s" ] || continue
    sync_one_spec "$s"
    synced=$((synced + 1))
  done
  if [ "$synced" -eq 0 ]; then
    sync_one_spec ""   # no active spec — initiative-only sync (unchanged behavior)
  fi
}

cmd_show() {
  local state_file
  # JUSTIFIED: no STATE.md yet is valid pre-sync — empty output, injection omitted
  state_file=$(ls -t "$INIT_DIR"/*.STATE.md 2>/dev/null | head -1)
  [ -z "$state_file" ] && return 0

  local updated phase tasks age_h now file_epoch
  updated=$(grep -m1 '^\- \*\*updated_at\*\*:' "$state_file" | sed 's/.*: //')
  phase=$(grep -m1 '^\- \*\*phase\*\*:' "$state_file" | sed 's/.*: //')
  tasks=$(grep -m1 '^\- \*\*tasks\*\*:' "$state_file" | sed 's/.*: //')
  now=$(date +%s)
  # JUSTIFIED: GNU-vs-BSD stat probe — epoch 0 fallback reads as very old, flagged below
  file_epoch=$(stat -f %m "$state_file" 2>/dev/null || stat -c %Y "$state_file" 2>/dev/null || echo 0)
  age_h=$(( (now - file_epoch) / 3600 ))

  if [ "$age_h" -gt 168 ]; then
    echo "[initiative] ⚠ STATE stale (${age_h}h old): $state_file — run \`bash .claude/scripts/initiative-state.sh sync\`"
  else
    echo "[initiative] $(basename "$state_file" .STATE.md): phase=$phase | $tasks | updated ${age_h}h ago — read $state_file for full state"
  fi
}

case "${1:-}" in
  sync) cmd_sync ;;
  show) cmd_show ;;
  *) echo "usage: initiative-state.sh sync|show" >&2; exit 1 ;;
esac
