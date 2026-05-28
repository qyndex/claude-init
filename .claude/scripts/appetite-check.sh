#!/usr/bin/env bash
# Appetite circuit-breaker — Round 7 B.
#
# Reads every initiative's appetite block, computes elapsed + spend, surfaces
# warnings at 50% and breaches at 100%. Default action = surface for review
# (per Round 7 operator pick); never auto-kills.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# Concurrency-safe TASKS.md mutation (Round 13 Fix 2).
. "$ROOT/.claude/scripts/lib/tasks-lib.sh"

# True if an OPEN ([ ]/[~]/[b]/[!]) breach task already exists for initiative $1.
# Stops the daily run from re-spamming a fresh breach task every 09:00.
_open_breach_exists() {
  awk -v id="$1" '
    /^- \[[ ~b!]\]/ { open=1 }
    /^- \[[xs]\]/    { open=0 }
    /summary: Initiative / { if (open && index($0, "Initiative " id " hit 100% appetite")) found=1 }
    END { exit !found }
  ' tasks/TASKS.md
}

AUDIT_DIR=".claude/memory/audits"
mkdir -p "$AUDIT_DIR"

warnings=0
breaches=0

for init in initiatives/active/*.md; do
  [ -f "$init" ] || continue

  id=$(grep -E '^id:' "$init" | head -1 | sed 's/id:[[:space:]]*//' | tr -d '"' | head -c 32)
  [ -z "$id" ] && continue

  declared_at=$(grep -E '^  declared_at:' "$init" | head -1 | sed 's/.*declared_at:[[:space:]]*//' | tr -d '"')
  time_str=$(grep -E '^  time:' "$init" | head -1 | sed 's/.*time:[[:space:]]*//' | head -c 10)
  budget=$(grep -E '^  budget_usd:' "$init" | head -1 | sed 's/.*budget_usd:[[:space:]]*//' | head -c 10)

  # Skip if appetite not declared
  [ -z "$declared_at" ] || [ -z "$time_str" ] && continue

  # Convert time spec (e.g., "6w") to seconds
  case "$time_str" in
    *w) appetite_days=$(( ${time_str%w} * 7 )) ;;
    *d) appetite_days=$(( ${time_str%d} )) ;;
    *)  appetite_days=42 ;;  # default 6w
  esac

  # JUSTIFIED: GNU/BSD date portability — GNU form tried first, BSD form is the fallback, and the final 0 sentinel marks an unparseable declared_at that the next line skips
  declared_epoch=$(date -d "$declared_at" +%s 2>/dev/null || date -j -f '%Y-%m-%d' "$declared_at" +%s 2>/dev/null || echo 0)
  [ "$declared_epoch" = "0" ] && continue

  now_epoch=$(date +%s)
  elapsed_days=$(( (now_epoch - declared_epoch) / 86400 ))
  elapsed_pct=$(awk "BEGIN { printf \"%.0f\", ($elapsed_days / $appetite_days) * 100 }")

  # Spend (best-effort; needs Round 7 E current-initiative attribution)
  spent="?"
  spent_pct="?"
  if [ -f .claude/hooks/.log/cost-summary.json ] && command -v jq >/dev/null 2>&1; then
    # JUSTIFIED: cost read guarded by the enclosing [ -f ] + command -v jq; the in-query // 0 defaults a never-billed initiative, the redirect only drops noise on a torn write
    spent=$(jq -r --arg id "$id" '.by_initiative[$id] // 0' .claude/hooks/.log/cost-summary.json 2>/dev/null)
    if [ -n "$budget" ] && [ "$budget" -gt 0 ]; then
      spent_pct=$(awk "BEGIN { printf \"%.0f\", ($spent / $budget) * 100 }")
    fi
  fi

  # Worst pct across time + spend dimensions
  worst_pct="$elapsed_pct"
  # JUSTIFIED: the redirect guards the numeric compare against a non-integer worst_pct; the leading "?" check already gates spent_pct, this is defense for worst_pct
  if [ "$spent_pct" != "?" ] && [ "$spent_pct" -gt "$worst_pct" ] 2>/dev/null; then
    worst_pct="$spent_pct"
  fi

  # JUSTIFIED: the redirect suppresses the "integer expression expected" message when worst_pct is the "?" sentinel (spend unknown); the test then fails closed, skipping the breach branch
  if [ "$worst_pct" -ge 100 ] 2>/dev/null; then
    # BREACH — write audit + task
    breach_file="$AUDIT_DIR/appetite-breach-${id}-$(date +%Y-%m-%d).md"
    cat > "$breach_file" <<EOF
# ⚠ Appetite breach — initiative $id

- declared: $declared_at
- appetite: $time_str ($appetite_days days)
- elapsed: $elapsed_days days (${elapsed_pct}%)
- spent: \$${spent} of \$${budget} (${spent_pct}%)

## Decision required
Per Shape Up: at 100% appetite, scope-hammer to ship what survives, OR /pivot.

Options:
- \`/pivot drop $id --reason "appetite breached without convergence"\`
- \`/pivot pause $id --until <date>\` — defer to next quarter
- \`/pivot supersede $id --by <new-id>\` — scope down to a smaller successor
- Extend (peer review required + must-have-only justification per initiative frontmatter)
EOF

    # Append to tasks — locked, section-aware, idempotent (Round 13 Fix 2).
    if [ -f tasks/TASKS.md ] && ! _open_breach_exists "$id"; then
      _append_breach_task() {
        local entry
        entry=$(cat <<EOF
- [!] T-$(tasks_next_id)  | priority: incident-followup  | created: $(date -Iseconds)
  summary: Initiative $id hit 100% appetite — decide /pivot drop|pause|supersede or extend
  files: $breach_file
  accept: /pivot decision recorded in pivots/active/ OR appetite extension justified in initiative frontmatter
  owner: @<initiative-owner>
  source: appetite-circuit-breaker
EOF
)
        tasks_append_active "$entry"
      }
      # JUSTIFIED: appending the breach task is best-effort surfacing; the fallback keeps a lock contention from aborting the daily run — the audit file is already written and the next run retries
      with_tasks_lock _append_breach_task || true
    fi
    breaches=$((breaches + 1))
    echo "  BREACH: $id at ${worst_pct}%"

  # JUSTIFIED: the redirect suppresses the "integer expression expected" message when worst_pct is the "?" sentinel; the test fails closed, skipping the warning branch
  elif [ "$worst_pct" -ge 50 ] 2>/dev/null; then
    # WARN — write audit
    warn_file="$AUDIT_DIR/appetite-warning-${id}-$(date +%Y-%m-%d).md"
    cat > "$warn_file" <<EOF
# Appetite warning — initiative $id

- elapsed: $elapsed_days/$appetite_days days (${elapsed_pct}%)
- spent: \$${spent} of \$${budget} (${spent_pct}%)

## Convergence check (Shape Up hill chart)
Are we uphill (still figuring out) or downhill (just executing)? Look at:
- Have all unknowns from the spec been resolved?
- Are remaining tasks well-defined (no \`[OQ]\` items)?
- Is the burndown trending toward ship-date?

If uphill at 50%, the project is at risk of appetite breach — consider scope-hammering NOW.
EOF
    warnings=$((warnings + 1))
    echo "  warning: $id at ${worst_pct}%"
  fi
done

echo
echo "appetite check: $warnings warnings, $breaches breaches"
[ "$breaches" -eq 0 ]
