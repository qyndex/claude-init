#!/usr/bin/env bash
# Scheduled ramp driver — e2e-audit release-deploy-3.
#
# The flag-rollout SKILL defines the ramp table (1% → 10% → 50% → 100% with
# per-stage waits and mechanical exit gates) but nothing DROVE it — flags sat
# at their last manual % forever and SHIPPED never fired. This script is the
# driver: run it on a schedule (ramp-check.yml, ~6h) or from /flag ramp.
#
# Per active spec with a ## Rollout block:
#   at 100%            → fire repository_dispatch flag-shipped (once) so
#                        issue-lifecycle.yml moves the spec issue to SHIPPED
#   mid-ramp, gate met → ramp to the next stage via the provider adapter
#   gate breached      → rollback-flag.sh (mechanical kill) + hotfix task
#   provider unwired   → LOUD task in tasks/TASKS.md (never a silent hold)
#
# State source: .claude/memory/flags/REGISTRY.md (last `| <flag> | <pct> | <date> |`
# row per flag — written here and by /flag). Gates: Prometheus error-rate via
# PROM_URL (same query family as canary-deploy.yml).
#
# Ramping is provider-specific (percentage APIs differ) — wire ONE of:
#   FLAG_RAMP_CMD      command invoked as: $FLAG_RAMP_CMD <flag> <pct>
#   FLAG_RAMP_WEBHOOK  POST {flag,pct} JSON
#
# Usage: ramp-check.sh [--dry-run]

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
. "$ROOT/.claude/scripts/lib/tasks-lib.sh"

DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
REGISTRY=".claude/memory/flags/REGISTRY.md"
now_epoch=$(date +%s)

# Append a loud operator task once (dedup on the summary).
loud_task() { # <summary>
  local s="$1"
  grep -qF "$s" tasks/TASKS.md 2>/dev/null && return 0
  [ "$DRY" = 1 ] && { echo "[dry-run] would create task: $s"; return 0; }
  local id entry
  id="$(tasks_next_id)"
  entry=$(printf -- '- [ ] T-%s  | priority: hotfix  | created: %s  | last_touched: %s\n  summary: %s\n  files: <tbd>\n  accept: <human decision required>\n  owner: @operator\n  source: ramp-check' \
    "$id" "$(date -Iseconds)" "$(date -Iseconds)" "$s")
  with_tasks_lock tasks_append_active "$entry"
  echo "  → task T-$id created: $s"
}

registry_last() { # <flag> -> "<pct> <date>" of the freshest row (ISO date has no spaces)
  [ -f "$REGISTRY" ] || return 1
  grep -E "^\| *${1} *\|" "$REGISTRY" | tail -1 \
    | awk -F'|' '{gsub(/^ +| +$/,"",$3); gsub(/^ +| +$/,"",$4); gsub(/ /,"_",$3); printf "%s %s", $3, $4}'
}

registry_append() { # <flag> <pct> <note>
  [ "$DRY" = 1 ] && return 0
  [ -f "$REGISTRY" ] || { mkdir -p "$(dirname "$REGISTRY")"; printf '# Flag registry\n\n' > "$REGISTRY"; }
  printf '| %s | %s | %s | %s |\n' "$1" "$2" "$(date -Iseconds)" "$3" >> "$REGISTRY"
}

ramp_to() { # <flag> <pct> -> 0 ok, 2 unwired/failed
  if [ "$DRY" = 1 ]; then echo "[dry-run] would ramp $1 → $2%"; return 0; fi
  if [ -n "${FLAG_RAMP_CMD:-}" ]; then
    $FLAG_RAMP_CMD "$1" "$2" || return 2
  elif [ -n "${FLAG_RAMP_WEBHOOK:-}" ]; then
    curl -fsS -X POST "$FLAG_RAMP_WEBHOOK" -H 'Content-Type: application/json' \
      -d "{\"flag\":\"$1\",\"pct\":$2}" >/dev/null || return 2
  else
    return 2
  fi
}

gate_error_rate() { # <service> -> echoes rate; rc 1 when unmeasurable
  [ -n "${PROM_URL:-}" ] || return 1
  curl -sG "$PROM_URL/api/v1/query" \
    --data-urlencode "query=sum(rate(http_requests_total{service=\"$1\",code=~\"5..\"}[30m])) / sum(rate(http_requests_total{service=\"$1\"}[30m]))" \
    | jq -r '.data.result[0].value[1] // "0"'
}

checked=0
for spec in specs/active/*.md; do
  [ -f "$spec" ] || continue
  grep -q '^## Rollout' "$spec" || continue
  grep -qE '^status: *(shipped|paused|dropped)' "$spec" && continue
  flag=$(awk '/^## Rollout/{r=1} r && /^  name:/{print $2; exit}' "$spec" | tr -d '"')
  [ -z "$flag" ] && continue
  checked=$((checked + 1))
  service=$(grep -E '^service:' "$spec" | head -1 | awk '{print $2}')
  threshold=$(awk '/^## Rollout/{r=1} r && /auto_rollback_threshold:/{print $2; exit}' "$spec" | tr -d '"')
  threshold="${threshold:-0.0144}"

  row=$(registry_last "$flag" || true)
  pct="${row%% *}"; since="${row#* }"
  case "$pct" in
    "")        echo "$flag: no registry row — not ramping yet (start via /flag ramp)"; continue ;;
    *KILLED*)  echo "$flag: KILLED — incident path owns it; skipping"; continue ;;
    *SHIPPED*) continue ;;
  esac

  if [ "$pct" = "100" ]; then
    issue=$(grep -E '^github_issue:' "$spec" | head -1 | awk '{print $2}' | tr -d '#')
    if [ -n "$issue" ] && command -v gh >/dev/null 2>&1 && [ "$DRY" = 0 ]; then
      if gh api "repos/{owner}/{repo}/dispatches" -f event_type=flag-shipped \
           -F "client_payload[issue_number]=$issue" >/dev/null 2>&1; then
        registry_append "$flag" "SHIPPED" "flag-shipped dispatched for issue #$issue"
        echo "$flag: 100% → flag-shipped fired (issue #$issue)"
      else
        loud_task "ramp-check: flag $flag at 100% but flag-shipped dispatch FAILED — fire manually: gh api repos/{owner}/{repo}/dispatches -f event_type=flag-shipped -F client_payload[issue_number]=$issue"
      fi
    else
      echo "$flag: at 100% (no github_issue / gh / dry-run — dispatch skipped)"
    fi
    continue
  fi

  # Stage table (flag-rollout SKILL): minimum soak before the next ramp.
  case "$pct" in
    1)  wait_h=24;  next=10  ;;
    10) wait_h=48;  next=50  ;;
    50) wait_h=72;  next=100 ;;
    *)  echo "$flag: unrecognized pct '$pct' in registry — holding"; continue ;;
  esac
  # JUSTIFIED: unparsable registry date degrades to epoch 0 = "soaked long enough"; the metric gate below still protects the ramp
  since_epoch=$(date -j -f '%Y-%m-%dT%H:%M:%S' "${since%%+*}" +%s 2>/dev/null || date -d "$since" +%s 2>/dev/null || echo 0)
  if [ $(( now_epoch - since_epoch )) -lt $(( wait_h * 3600 )) ]; then
    echo "$flag: $pct% soaking ($(( (now_epoch - since_epoch) / 3600 ))h/${wait_h}h) — hold"
    continue
  fi

  err=$(gate_error_rate "${service:-$flag}" || true)
  if [ -z "$err" ]; then
    loud_task "ramp-check: flag $flag ramp due ($pct% soaked ${wait_h}h) but PROM_URL is unwired — gates cannot be evaluated; wire observability (docs/DEPLOY-INTEGRATION.md §1) or ramp manually via /flag"
    continue
  fi
  if awk "BEGIN{exit !($err > $threshold)}"; then
    echo "$flag: GATE BREACH at $pct% (err=$err > $threshold) — mechanical kill"
    if bash .claude/scripts/rollback-flag.sh "$flag" --reason "ramp-check gate breach err=$err at ${pct}%"; then
      registry_append "$flag" "KILLED (0%)" "ramp-check breach err=$err"
    fi
    loud_task "ramp-check: flag $flag rolled back at $pct% (error rate $err > $threshold) — investigate before re-ramping (spec $spec)"
    continue
  fi

  if ramp_to "$flag" "$next"; then
    registry_append "$flag" "$next" "ramp-check: gate met (err=$err ≤ $threshold) after ${wait_h}h at $pct%"
    echo "$flag: ramped $pct% → $next%"
  else
    loud_task "ramp-check: flag $flag ramp due ($pct% → $next%) but NO ramp provider is wired — set FLAG_RAMP_CMD or FLAG_RAMP_WEBHOOK, or ramp manually via /flag ramp $flag"
  fi
done

echo "ramp-check: $checked rollout spec(s) evaluated"
