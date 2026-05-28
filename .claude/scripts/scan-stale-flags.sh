#!/usr/bin/env bash
# Stale-flag scanner — Round 13 (closes the dangling ref in flag-cleanup.md).
#
# Finds feature flags at 100% rollout older than their spec's `cleanup_after`,
# and opens cleanup tasks in tasks/TASKS.md (priority: cleanup, flag: <name>).
# These are autopilot-eligible (low-risk, well-defined).
#
# Source of flag state (in priority order):
#   1. The flag provider (OpenFeature/PostHog/LaunchDarkly) if a query is wired
#   2. .claude/memory/flags/REGISTRY.md (the local flag ledger)
#   3. Each spec's ## Rollout block (flag.name + cleanup_after)
#
# Writes via the locked TASKS.md helper (Round 13 Fix 2) to avoid races.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

now_epoch=$(date +%s)
candidates=0

# Walk specs that declare a flag + cleanup_after
for spec in specs/active/*.md specs/archive/*.md specs/archive/*/*.md; do
  [ -f "$spec" ] || continue
  # JUSTIFIED: awk over a spec from the glob; the redirect guards a file removed mid-walk — a spec without a flag name yields empty, skipped by the guard on line 28
  flag=$(awk '/^  name:/{print $2; exit}' "$spec" 2>/dev/null | tr -d '"')
  # JUSTIFIED: optional field read; the redirect guards a vanished file — a spec without cleanup_after yields empty, skipped by the guard on line 28
  cleanup_after=$(grep -E 'cleanup_after:' "$spec" 2>/dev/null | head -1 | grep -oE '[0-9]+d' | grep -oE '[0-9]+')
  [ -z "$flag" ] || [ -z "$cleanup_after" ] && continue

  # When did it hit 100%? Heuristic: flag registry, else spec `updated:` date.
  hit_100=""
  if [ -f .claude/memory/flags/REGISTRY.md ]; then
    # JUSTIFIED: registry lookup guarded by the enclosing [ -f ]; the redirect tolerates a flag not yet recorded — empty result falls through to the spec `updated:` heuristic below
    hit_100=$(grep -E "$flag.*100" .claude/memory/flags/REGISTRY.md 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
  fi
  [ -z "$hit_100" ] && hit_100=$(grep -E '^updated:' "$spec" | head -1 | sed 's/updated:[[:space:]]*//' | tr -d ' ')
  [ -z "$hit_100" ] && continue

  # JUSTIFIED: GNU/BSD date portability — GNU form tried first, BSD form is the fallback, and a final 0 sentinel marks an unparseable date that the guard below skips
  hit_epoch=$(date -d "$hit_100" +%s 2>/dev/null || date -j -f '%Y-%m-%d' "$hit_100" +%s 2>/dev/null || echo 0)
  [ "$hit_epoch" = "0" ] && continue

  age_days=$(( (now_epoch - hit_epoch) / 86400 ))
  if [ "$age_days" -gt "$cleanup_after" ]; then
    echo "  stale flag: $flag (100% for ${age_days}d > cleanup_after ${cleanup_after}d)"
    # Idempotent: skip if a cleanup task for this flag already exists
    # JUSTIFIED: idempotency probe — the redirect tolerates a missing TASKS.md on a fresh repo; absence correctly means "not yet queued" so we proceed to queue
    if grep -q "flag: $flag" tasks/TASKS.md 2>/dev/null; then
      echo "    (cleanup task already queued)"
      continue
    fi
    printf -- '- [ ] flag-cleanup: %s (100%% for %dd)\n' "$flag" "$age_days" > /tmp/flag-finding.md
    # JUSTIFIED: queuing the cleanup task is best-effort; the redirect+fallback keep one transient append failure from aborting the whole spec walk (next nightly run retries)
    bash .claude/scripts/findings-to-tasks.sh /tmp/flag-finding.md \
      --priority cleanup --source "scan-stale-flags" --default-owner "@platform" 2>/dev/null || true
    rm -f /tmp/flag-finding.md
    candidates=$((candidates + 1))
  fi
done

echo "scan-stale-flags: $candidates cleanup task(s) queued"
