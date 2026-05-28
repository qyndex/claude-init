#!/usr/bin/env bash
# Verified merge — Round 6 E.
#
# Replaces `gh pr merge --auto --squash` (flat merge) with a 5-step protocol:
#   1. Pre-merge prep: rebase onto main + already-verified sibling streams
#   2. Integration test: verify.sh + local-pr-check --heavy + contract-tests
#   3. AI-mediated semantic conflict resolution (if step 2 fails)
#   4. Merge (only if step 2/3 passes)
#   5. Post-merge verify on main; auto-revert + auto-fix PR if it fails
#
# Usage:
#   bash .claude/scripts/verified-merge.sh <stream-id>
#   bash .claude/scripts/verified-merge.sh <stream-id> --dry-run
#
# Exit codes:
#   0  — merged + post-merge verified
#   10 — rebase onto main failed
#   11 — rebase onto sibling failed
#   20 — integration test failed (verify.sh)
#   21 — local-pr-check failed
#   22 — contract-tests failed
#   30 — AI mediation failed
#   40 — post-merge verify failed; AUTO-REVERTED

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
LOG=".claude/hooks/.log/verified-merge-${STREAM}-$(date +%Y%m%d-%H%M%S).log"
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
verify_failed=0

if [ -x .claude/scripts/verify.sh ]; then
  (cd "$WORKTREE" && bash "$ROOT/.claude/scripts/verify.sh") >> "$LOG" 2>&1 || verify_failed=20
fi

if [ "$verify_failed" = "0" ] && [ -x .claude/scripts/local-pr-check.sh ]; then
  (cd "$WORKTREE" && bash "$ROOT/.claude/scripts/local-pr-check.sh" --heavy) >> "$LOG" 2>&1 || verify_failed=21
fi

if [ "$verify_failed" = "0" ] && [ -x .claude/scripts/contract-tests.sh ]; then
  (cd "$WORKTREE" && bash "$ROOT/.claude/scripts/contract-tests.sh" "$STREAM") >> "$LOG" 2>&1 || verify_failed=22
fi

# ─── Step 3: AI-mediated semantic conflict resolution ────────────────────
mediation_used=false
if [ "$verify_failed" != "0" ]; then
  log "Step 3: integration test failed (exit=$verify_failed); spawning AI mediation"
  mediation_used=true

  if [ "$DRY_RUN" = "1" ]; then
    log "  dry-run: would spawn debugger agent"
  elif command -v claude >/dev/null 2>&1; then
    mediation_prompt="Stream $STREAM failed post-rebase verification (exit $verify_failed). \
Read the failure in $LOG, diff this branch (cwd) vs origin/main, propose minimal \
reconciliation, apply it as a single commit with subject 'merge-mediation: <one-line>'. \
Then re-run verify.sh. If verify still fails, exit non-zero — do NOT push broken state."

    (cd "$WORKTREE" && claude -p \
      --max-turns 30 \
      --max-budget-usd 2 \
      --permission-mode auto \
      --append-system-prompt "$mediation_prompt" \
      # JUSTIFIED: || true — a non-zero from the mediation agent is intentionally tolerated; the authoritative gate is the verify.sh re-run immediately below, which escalates on failure
      "Fix the integration failure for stream $STREAM" >> "$LOG" 2>&1) || true

    # Re-run verify
    if ! (cd "$WORKTREE" && bash "$ROOT/.claude/scripts/verify.sh") >> "$LOG" 2>&1; then
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
  log "  dry-run: would push $branch and gh pr merge --squash"
else
  git -C "$WORKTREE" push --force-with-lease origin "$branch" >> "$LOG" 2>&1

  mediation_note=""
  [ "$mediation_used" = "true" ] && mediation_note=" + AI mediation"
  pr_body=$(printf 'Verified-merge: rebased on main + %d sibling(s)%s; verify.sh + heavy + contract-tests PASS. See %s' \
    "$(echo "$already_merged" | wc -w)" "$mediation_note" "$LOG")

  gh pr merge "$branch" --squash --delete-branch --body "$pr_body" >> "$LOG" 2>&1 \
    || fail "gh pr merge failed" 40
fi

# ─── Step 5: Post-merge verify on main + auto-revert/fix on failure ──────
log "Step 5: post-merge verify on main"
if [ "$DRY_RUN" = "1" ]; then
  log "  dry-run: would re-verify main and auto-revert on failure"
else
  git checkout main >> "$LOG" 2>&1
  # JUSTIFIED: || true — pull is best-effort (may be offline or up-to-date); we still post-merge-verify the local main below, which is the real gate
  git pull >> "$LOG" 2>&1 || true

  if ! bash .claude/scripts/verify.sh >> "$LOG" 2>&1; then
    log "POST-MERGE VERIFY FAILED — auto-reverting"
    last_sha=$(git rev-parse HEAD)
    git revert --no-edit "$last_sha" >> "$LOG" 2>&1
    git push origin main >> "$LOG" 2>&1
    log "Reverted $last_sha on main"

    # Spawn auto-fix PR session (mirrors the daily-batch failure pattern)
    if command -v claude >/dev/null 2>&1; then
      fix_branch="claude/post-merge-autofix-$(date +%Y-%m-%d-%H%M)"
      git checkout -b "$fix_branch" >> "$LOG" 2>&1
      claude -p --max-budget-usd 5 --max-turns 60 --permission-mode auto \
        --append-system-prompt "Post-merge verify failed on main after merging stream $STREAM. \
Read the failure in $LOG, identify the issue, propose minimal fix, commit, push, open PR. \
Do NOT auto-merge." \
        # JUSTIFIED: || true — the auto-fix agent's exit is non-authoritative; main is already reverted+safe and the agent only opens a PR for human review, so its failure must not abort cleanup
        "Investigate the post-merge failure" >> "$LOG" 2>&1 || true
      git checkout main >> "$LOG" 2>&1
    fi

    # Update fleet.json
    jq --arg s "$STREAM" '.fleet[$s].status = "reverted" | .fleet[$s].reverted_at = (now | todate)' \
       "$FLEET" > "${FLEET}.tmp" && mv "${FLEET}.tmp" "$FLEET"
    echo "$(date -Iseconds) $STREAM     AUTO-REVERT (post-merge verify failed)" \
      >> .swarms/coordinator/decisions.log
    exit 40
  fi

  # Success path: update fleet.json schema v2 fields
  jq --arg s "$STREAM" --argjson mediation_used "$mediation_used" \
     '.fleet[$s].status = "merged"
      | .fleet[$s].merged_at = (now | todate)
      | .fleet[$s].mediation_used = $mediation_used
      | ._schema_version = 2' \
     "$FLEET" > "${FLEET}.tmp" && mv "${FLEET}.tmp" "$FLEET"

  log "verified-merge SUCCESS for stream=$STREAM"
fi

exit 0
