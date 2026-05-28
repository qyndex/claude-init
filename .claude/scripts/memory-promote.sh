#!/usr/bin/env bash
# Memory v2 — mechanical promotion/decay (Round 5 C4).
#
# Run nightly from .claude/routines/dream-cron.yml. Reads index.jsonl + git log,
# updates `status:` fields in memory markdown files based on observed evidence.
#
# Rules (mirror what the templates promise but nobody enforced):
#
#   patterns/<x>.md:
#     emerging  → established   when verified_in_commits ≥ 3 AND ≥ 2 distinct module prefixes
#     established → deprecated  when superseded_by points at a newer pattern or ADR
#     ANY → quarantine          when recurred_anti ≥ 3 (the anti-pattern keeps showing up)
#
#   decisions/<x>.md:
#     accepted → stale_unverified   when (now - last_verified) > 365d
#     accepted → superseded         when another ADR's `Supersedes:` field names this
#
#   incidents/<x>.md:
#     no auto-promotion; recurred_at counter is bumped by reviewer/security agents.
#
# Output: a `.claude/memory/audits/promote-<date>.md` audit report.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

INDEX=".claude/memory/index.jsonl"
[ -f "$INDEX" ] || { echo "Index missing — run: bash .claude/scripts/memory-index.sh backfill" >&2; exit 1; }

NOW_EPOCH=$(date +%s)
YEAR_AGO_EPOCH=$(( NOW_EPOCH - 365 * 86400 ))
AUDIT_DIR=".claude/memory/audits"
mkdir -p "$AUDIT_DIR"
REPORT="$AUDIT_DIR/promote-$(date +%Y-%m-%d).md"

declare -i promoted=0 demoted=0 quarantined=0 stale_flagged=0

{
  echo "# Memory promotion audit — $(date -Iseconds)"
  echo
  echo "Reads .claude/memory/index.jsonl + git log; mutates status fields per rules in memory-promote.sh."
  echo

  # ─── PATTERNS: emerging → established ────────────────────────────────
  echo "## Patterns promoted (emerging → established)"
  while IFS= read -r entry; do
    path=$(echo "$entry" | jq -r .path)
    status=$(echo "$entry" | jq -r .status)
    id=$(echo "$entry" | jq -r .id)
    type=$(echo "$entry" | jq -r .type)

    [ "$type" = "pattern" ] || continue
    [ "$status" = "emerging" ] || continue

    # Read verified_in_commits from the file directly (not all in index)
    # JUSTIFIED: a pattern file with no verified_in_commits field makes grep exit non-zero — counting to 0 is the correct "not yet promotable" outcome, not a failure
    commits_count=$(grep -oE 'verified_in_commits:\s*\[[^]]*\]' "$path" 2>/dev/null | \
      grep -oE '[a-f0-9]{7,40}' | wc -l | tr -d ' ')

    # Count distinct module prefixes from paths_touched
    # JUSTIFIED: an entry with an empty paths_touched array yields no output from jq — zero distinct modules is the correct value and blocks promotion, as intended
    distinct_mods=$(echo "$entry" | jq -r '.paths_touched[]' 2>/dev/null | \
      awk -F'/' '{print $1"/"$2}' | sort -u | wc -l | tr -d ' ')

    if [ "$commits_count" -ge 3 ] && [ "$distinct_mods" -ge 2 ]; then
      sed -i.bak "s/^- \\*\\*Status\\*\\*: emerging/- **Status**: established/" "$path"
      rm -f "${path}.bak"
      echo "- $id (commits=$commits_count, modules=$distinct_mods)"
      promoted+=1
    fi
  done < "$INDEX"
  [ "$promoted" -eq 0 ] && echo "_(none)_"
  echo

  # ─── DECISIONS: accepted >12mo without last_verified ────────────────
  echo "## Decisions flagged stale (>12mo, no recent last_verified)"
  while IFS= read -r entry; do
    path=$(echo "$entry" | jq -r .path)
    status=$(echo "$entry" | jq -r .status)
    type=$(echo "$entry" | jq -r .type)
    last_verified=$(echo "$entry" | jq -r .last_verified)
    created=$(echo "$entry" | jq -r .created)
    id=$(echo "$entry" | jq -r .id)
    owners=$(echo "$entry" | jq -r '.owners | join(",")')

    [ "$type" = "decision" ] || continue
    [ "$status" = "accepted" ] || continue

    # Use last_verified if present, else created
    check_date="$last_verified"
    [ -z "$check_date" ] || [ "$check_date" = "null" ] && check_date="$created"
    [ -z "$check_date" ] || [ "$check_date" = "null" ] && continue

    # JUSTIFIED: GNU date form tried first then the BSD form; an unparseable date falls to epoch 0, and the guard below ignores 0 so a malformed date never gets stale-flagged
    check_epoch=$(date -d "$check_date" +%s 2>/dev/null || date -j -f '%Y-%m-%d' "$check_date" +%s 2>/dev/null || echo 0)
    if [ "$check_epoch" -gt 0 ] && [ "$check_epoch" -lt "$YEAR_AGO_EPOCH" ]; then
      echo "- $id (last touched $check_date, owners: ${owners:-unowned})"
      stale_flagged+=1
    fi
  done < "$INDEX"
  [ "$stale_flagged" -eq 0 ] && echo "_(none)_"
  echo

  # ─── PATTERNS quarantined for repeated anti-pattern violations ──────
  echo "## Patterns quarantined (recurred_anti ≥ 3)"
  for f in .claude/memory/patterns/*.md; do
    [ -f "$f" ] || continue
    case "$f" in *0000-template.md) continue ;; esac

    # JUSTIFIED: a pattern file without a recurred_anti field makes grep find nothing and exit non-zero — defaulting to 0 keeps it out of quarantine, the intended behavior
    recurred=$(grep -oE 'recurred_anti:\s*[0-9]+' "$f" 2>/dev/null | head -1 | grep -oE '[0-9]+$' || echo 0)
    if [ "$recurred" -ge 3 ]; then
      id=$(basename "$f" .md)
      # Don't double-quarantine
      if ! grep -q '^- \*\*Status\*\*: quarantined' "$f"; then
        sed -i.bak 's/^- \*\*Status\*\*: \(established\|emerging\)/- **Status**: quarantined/' "$f"
        rm -f "${f}.bak"
        echo "- $id (recurred_anti=$recurred — consider /codify-rule)"
        quarantined+=1
      fi
    fi
  done
  [ "$quarantined" -eq 0 ] && echo "_(none)_"
  echo

  # ─── Summary ─────────────────────────────────────────────────────────
  echo "## Summary"
  echo
  echo "| Action | Count |"
  echo "|---|---|"
  echo "| Patterns promoted | $promoted |"
  echo "| Patterns quarantined | $quarantined |"
  echo "| Decisions stale-flagged | $stale_flagged |"
  echo

  if [ "$stale_flagged" -gt 0 ]; then
    echo "**Action required**: re-verify the stale ADRs above or mark them \`superseded\`. Owners can run:"
    echo "  \`/adr-walk --verify-links\` to start re-verification flow."
  fi
} > "$REPORT"

# Rebuild index after mutations
if [ "$promoted" -gt 0 ] || [ "$quarantined" -gt 0 ]; then
  bash .claude/scripts/memory-index.sh rebuild >/dev/null 2>&1
fi

echo "✓ Wrote $REPORT (promoted=$promoted, quarantined=$quarantined, stale=$stale_flagged)"
