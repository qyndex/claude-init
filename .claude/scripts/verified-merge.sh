#!/usr/bin/env bash
# Verified merge — Round 6 E.
#
# Replaces `gh pr merge --auto --squash` (flat merge) with a 5-step protocol:
#   1. Pre-merge prep: rebase onto main + already-verified sibling streams
#   2. Integration test: verify.sh + local-pr-check --heavy + contract-tests
#   3. AI-mediated semantic conflict resolution (if step 2 fails)
#   4. Request protected factory integration (only if step 2/3 passes)
# Remote receipts establish actual merge; rollback uses an approved PR.
#
# Usage:
#   bash .claude/scripts/verified-merge.sh <stream-id>
#   bash .claude/scripts/verified-merge.sh <stream-id> --dry-run
#
# Exit codes:
#   0  — integration request submitted, or dry-run verification passed
#   10 — rebase onto main failed
#   11 — rebase onto sibling failed
#   20 — integration test failed (verify.sh)
#   21 — local-pr-check failed
#   22 — contract-tests failed
#   30 — AI mediation failed
#   41 — PR create/checks/integration request failed

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

STREAM="${1:-}"
DRY_RUN=0
[ "${2:-}" = "--dry-run" ] && DRY_RUN=1

if [ -z "$STREAM" ]; then
  echo "Usage: $0 <stream-id> [--dry-run]" >&2
  exit 1
fi

FLEET=".swarms/coordinator/fleet.json"
WORKTREE=".claude/worktrees/$STREAM"
# LOG must be ABSOLUTE (e2e-audit swarm-2 follow-on): the mediation/auto-fix
# redirects happen inside `cd "$WORKTREE"` subshells — a relative path fails to
# resolve there, killing the whole command before claude ever spawns.
LOG="$ROOT/.claude/hooks/.log/verified-merge-${STREAM}-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .claude/hooks/.log

log() { printf '[%s] %s\n' "$(date -Iseconds)" "$*" | tee -a "$LOG" >&2; }
fail() { log "FAIL: $*"; exit "${2:-1}"; }

# escalate <reason> <exit-code> — durable handling for a merge-BLOCKING failure.
# Round 13 Fix 3: previously the non-recoverable exits (10/11/20/21/22/30) only wrote
# to $LOG, so an autonomous swarm/overnight run left a stream silently un-merged with a
# log nobody reads. Now we mark the stream blocked in the fleet, append to decisions.log,
# and queue a durable triage task — the same surfacing the exit-40 path already gets.
escalate() {
  local reason="$1" code="${2:-1}"
  log "ESCALATE: $reason (exit $code)"
  if [ -f "$FLEET" ]; then
    # JUSTIFIED: jq stderr suppressed and || true — best-effort fleet-status write inside escalate(); a failure must not mask the original blocking failure we're about to exit on
    jq --arg s "$STREAM" --arg r "$reason" \
       '.fleet[$s].status = "blocked" | .fleet[$s].blocked_reason = $r | .fleet[$s].blocked_at = (now|todate)' \
       "$FLEET" > "${FLEET}.tmp" 2>/dev/null && mv "${FLEET}.tmp" "$FLEET" || true
  fi
  mkdir -p .swarms/coordinator
  echo "$(date -Iseconds) $STREAM     BLOCKED ($reason) — see $LOG" >> .swarms/coordinator/decisions.log
  if [ -f tasks/TASKS.md ] && [ -x .claude/scripts/findings-to-tasks.sh ]; then
    local tf; tf="$(mktemp)"
    echo "- [ ] verified-merge blocked for stream $STREAM: $reason — triage $LOG (owner: @oncall)" > "$tf"
    # JUSTIFIED: || true — queuing the triage task is best-effort surfacing inside escalate(); its failure must not prevent the exit that propagates the real blocking code
    bash .claude/scripts/findings-to-tasks.sh "$tf" --priority incident-followup --source "verified-merge:$STREAM" >/dev/null 2>&1 || true
    rm -f "$tf"
  fi
  exit "$code"
}

[ -d "$WORKTREE" ] || fail "worktree not found: $WORKTREE" 1
[ -f "$FLEET" ] || fail "fleet.json missing" 1
WORKTREE="$(cd "$WORKTREE" && pwd)" || exit 1
already_merged=""

branch=$(jq -r --arg s "$STREAM" '.fleet[$s].branch // ""' "$FLEET")
[ -z "$branch" ] && fail "branch not found in fleet.json for stream: $STREAM" 1

log "verified-merge for stream=$STREAM branch=$branch (dry_run=$DRY_RUN)"

# ─── Step 1: Pre-merge prep — rebase onto main + verified siblings ───────
log "Step 1: rebase onto main + already-merged siblings"
git -C "$WORKTREE" fetch origin main >> "$LOG" 2>&1

if [ "$DRY_RUN" = "0" ]; then
  if ! git -C "$WORKTREE" rebase origin/main >> "$LOG" 2>&1; then
    # JUSTIFIED: || true — the rebase already failed; aborting is cleanup and may itself report "no rebase in progress", which is harmless before we escalate
    git -C "$WORKTREE" rebase --abort >> "$LOG" 2>&1 || true
    escalate "rebase onto main failed — likely textual conflict; human required" 10
  fi

  # Rebase onto each already-merged sibling so we catch semantic deps
  already_merged=$(jq -r '.fleet | to_entries[] | select(.value.status == "merged") | .key' "$FLEET")
  for sib in $already_merged; do
    [ "$sib" = "$STREAM" ] && continue
    sib_branch=$(jq -r --arg s "$sib" '.fleet[$s].branch // ""' "$FLEET")
    [ -z "$sib_branch" ] && continue
    log "  rebasing onto $sib_branch"
    # JUSTIFIED: || true — sibling fetch is best-effort; if the ref is already local the rebase below still proceeds, and a fetch miss surfaces as a rebase failure handled next
    git -C "$WORKTREE" fetch origin "$sib_branch" >> "$LOG" 2>&1 || true
    if ! git -C "$WORKTREE" rebase "origin/$sib_branch" >> "$LOG" 2>&1; then
      # JUSTIFIED: || true — rebase already failed; aborting is cleanup that may report "no rebase in progress", harmless before escalate
      git -C "$WORKTREE" rebase --abort >> "$LOG" 2>&1 || true
      escalate "rebase onto sibling $sib_branch failed" 11
    fi
  done
fi

# ─── Step 2: Integration test ────────────────────────────────────────────
log "Step 2: integration test on rebased branch"
run_integration_checks() {
  local gate
  for gate in verify.sh local-pr-check.sh contract-tests.sh; do
    [ -f "$ROOT/.claude/scripts/$gate" ] || { log "required gate missing: $gate"; return 20; }
  done
  bash "$ROOT/.claude/scripts/verify.sh" --root "$WORKTREE" >> "$LOG" 2>&1 || return 20
  bash "$ROOT/.claude/scripts/local-pr-check.sh" --root "$WORKTREE" --heavy >> "$LOG" 2>&1 || return 21
  (cd "$WORKTREE" && bash "$ROOT/.claude/scripts/contract-tests.sh" "$STREAM") >> "$LOG" 2>&1 || return 22
}
verify_failed=0
run_integration_checks || verify_failed=$?

# ─── Step 3: AI-mediated semantic conflict resolution ────────────────────
mediation_used=false
if [ "$verify_failed" != "0" ]; then
  log "Step 3: integration test failed (exit=$verify_failed); spawning AI mediation"
  mediation_used=true

  if [ "$DRY_RUN" = "1" ]; then
    escalate "dry-run integration failed (exit $verify_failed); no merge authorized" "$verify_failed"
  elif command -v claude >/dev/null 2>&1; then
    mediation_prompt="Stream $STREAM failed post-rebase verification (exit $verify_failed). \
Read the failure in $LOG, diff this branch (cwd) vs origin/main, propose minimal \
reconciliation, apply it as a single commit with subject 'merge-mediation: <one-line>'. \
Then re-run verify.sh. If verify still fails, exit non-zero — do NOT push broken state."

    # JUSTIFIED: || true — a non-zero from the mediation agent is intentionally tolerated; the authoritative gate is the verify.sh re-run immediately below, which escalates on failure
    # (e2e-audit swarm-2: comment moved ABOVE the command — a comment line inside a
    # backslash continuation TERMINATES it, severing the prompt arg + log redirect)
    (cd "$WORKTREE" && claude -p \
      --max-turns 30 \
      --max-budget-usd 2 \
      --permission-mode auto \
      --append-system-prompt "$mediation_prompt" \
      "Fix the integration failure for stream $STREAM" >> "$LOG" 2>&1) || true

    # Re-run every required integration gate after candidate changes.
    if ! run_integration_checks; then
      escalate "AI mediation did not resolve integration failure (exit $verify_failed)" 30
    fi
    log "  AI mediation resolved"
  else
    escalate "integration test failed (exit $verify_failed) and no claude CLI for mediation" "$verify_failed"
  fi
fi

# ─── Step 4: Merge ───────────────────────────────────────────────────────
log "Step 4: push + merge"
if [ "$DRY_RUN" = "1" ]; then
  log "  dry-run: would push $branch and request protected factory integration"
else
  git -C "$WORKTREE" push --force-with-lease origin "$branch" >> "$LOG" 2>&1

  mediation_note=""
  [ "$mediation_used" = "true" ] && mediation_note=" + AI mediation"
  # e2e-audit swarm-3: embed the evidence bundle path per §VII.7 when one exists
  evidence_note=""
  # JUSTIFIED: glob probe — no evidence dir for this stream just leaves the note blank
  evidence_dir=$(ls -dt verify/*-"${STREAM#feat-}"* verify/*-"$STREAM"* 2>/dev/null | head -1)
  [ -n "$evidence_dir" ] && evidence_note=" Evidence: $evidence_dir/"
  pr_body=$(printf 'Verified-merge: rebased on main + %d sibling(s)%s; verify.sh + heavy + contract-tests PASS.%s See %s' \
    "$(echo "$already_merged" | wc -w)" "$mediation_note" "$evidence_note" "$LOG")

  # e2e-audit swarm-3: full PR lifecycle — create the PR when none exists, WAIT
  # for the required checks, and only then merge. Previously a missing PR
  # dead-ended ("no PR found") on protected repos and merged INSTANTLY around
  # review on unprotected ones. All failures route through escalate() exit 41.
  if ! gh pr view "$branch" >> "$LOG" 2>&1; then
    (cd "$WORKTREE" && gh pr create --fill --body "$pr_body") >> "$LOG" 2>&1 \
      || escalate "gh pr create failed for $branch" 41
  fi
  if ! gh pr checks "$branch" --watch --fail-fast >> "$LOG" 2>&1; then
    escalate "PR checks failed for $branch — fix the red check, do not merge around it" 41
  fi
  pr_number=$(gh pr view "$branch" --json number --jq .number) \
    || escalate "cannot resolve candidate PR" 41
  bash "$ROOT/.claude/scripts/autonomous-ship.sh" "$pr_number" >> "$LOG" 2>&1 \
    || escalate "factory integration request failed" 41
fi

# The protected coordinator owns the actual merge and emits the remote receipt.
# Local success means request submitted; fleet reconciliation must observe merge.
if [ "$DRY_RUN" != "1" ]; then
  jq --arg s "$STREAM" '.fleet[$s].status = "merge-requested" | .fleet[$s].merge_requested_at = (now | todate)' \
    "$FLEET" > "${FLEET}.tmp" && mv "${FLEET}.tmp" "$FLEET"
fi
log "Factory integration requested; remote merge receipt pending"
exit 0
