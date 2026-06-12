#!/usr/bin/env bash
# feedback-score.sh — gap-audit G59/G61.
# Triage ranking used to live entirely inside an LLM prompt — irreproducible
# and untestable. This is the deterministic scorer: the LLM still clusters and
# narrates, but the RANKING comes from here.
#
#   score = severity_weight × arr_weight × renewal_multiplier
#     severity: P0=8  P1=4  P2=2  P3=1   (missing → 1)
#     arr_band: ENT=4 MID=2 SMB=1        (missing → 1, counted for the G61 warning)
#     renewal:  ≤30d ×3   ≤90d ×2   else ×1   (missing → 1)
#
# Usage: bash feedback-score.sh [<feedback-dir>]      # default .claude/memory/feedback/active
# Output: ranked TSV  score<TAB>id<TAB>severity<TAB>arr<TAB>renewal<TAB>problem_area
# G61: warns on stderr when >50% of entries lack arr_band — revenue-weighted
# ranking degrades VISIBLY, never silently.

set -uo pipefail

DIR="${1:-.claude/memory/feedback/active}"
[ -d "$DIR" ] || { echo "no $DIR — nothing to score"; exit 0; }

today_s=$(date +%s)
total=0
no_arr=0
rows=""

for f in "$DIR"/FB-*.md; do
  [ -f "$f" ] || continue
  total=$((total + 1))

  fb_id=$(grep -m1 -E '^id:' "$f" | sed 's/id:[[:space:]]*//' | tr -d ' ')
  [ -z "$fb_id" ] && fb_id=$(basename "$f" .md)
  sev=$(grep -m1 -E '^severity:' "$f" | grep -oE 'P[0-3]' | head -1)
  arr=$(grep -m1 -E '^[[:space:]]*arr_band:' "$f" | grep -oE 'SMB|MID|ENT' | head -1)
  renewal=$(grep -m1 -E '^[[:space:]]*contract_renewal:' "$f" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
  area=$(grep -m1 -E '^problem_area:' "$f" | sed 's/problem_area:[[:space:]]*//' | sed 's/[[:space:]]*#.*$//' | tr -d ' ')

  case "$sev" in P0) sw=8 ;; P1) sw=4 ;; P2) sw=2 ;; *) sw=1 ;; esac
  case "$arr" in ENT) aw=4 ;; MID) aw=2 ;; SMB) aw=1 ;; *) aw=1; no_arr=$((no_arr + 1)) ;; esac

  rm=1
  if [ -n "$renewal" ]; then
    # JUSTIFIED: both date flavors muted — an unparseable renewal date degrades to multiplier 1, never a crash
    renewal_s=$(date -j -f '%Y-%m-%d' "$renewal" +%s 2>/dev/null || date -d "$renewal" +%s 2>/dev/null || echo "")
    if [ -n "$renewal_s" ]; then
      days=$(( (renewal_s - today_s) / 86400 ))
      if [ "$days" -ge 0 ] && [ "$days" -le 30 ]; then rm=3
      elif [ "$days" -gt 30 ] && [ "$days" -le 90 ]; then rm=2
      fi
    fi
  fi

  score=$((sw * aw * rm))
  rows="${rows}${score}\t${fb_id}\t${sev:-?}\t${arr:--}\t${renewal:--}\t${area:--}\n"
done

if [ "$total" -eq 0 ]; then
  echo "no FB entries in $DIR — nothing to score"
  exit 0
fi

printf 'score\tid\tseverity\tarr\trenewal\tproblem_area\n'
printf "$rows" | sort -t$'\t' -k1,1nr

# ─── G61: visible degradation when revenue data is absent ────────────────
if [ "$total" -gt 0 ] && [ $((no_arr * 100 / total)) -gt 50 ]; then
  echo "⚠ ${no_arr}/${total} FB entries lack arr_band — revenue weighting is mostly neutral. ARR fields are OPERATOR-SUPPLIED (no billing source is wired by default); fill customer.arr_band via /feedback log --arr, or wire a billing source (Stripe MCP / accounts CSV)." >&2
fi
