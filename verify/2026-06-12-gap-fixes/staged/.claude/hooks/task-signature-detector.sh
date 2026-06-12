#!/usr/bin/env bash
# Task signature detector — Round 9 A.
#
# Stop hook. Scans the rolling bash log for repeated multi-step Bash sequences;
# emits skill-creator candidates when the same 3+ command chain appears ≥5×
# across ≥2 distinct sessions.
#
# Output: candidates appended to .claude/memory.proposed/skills/_candidates.jsonl
# auto-dream-check.sh (next Stop) reads candidates and invokes skill-creator.
#
# Hard rules:
#   - Only matches command FAMILIES (npm + git etc.), not exact arg strings (PII safe).
#   - Sessions = file-mtime gaps > 1h in bash.log
#   - Exit 0 ratio ≥ 80% required (filters out repeated failures = bug pattern, not skill candidate)
#   - Per-day candidate cap 5 (rate-limit)

set -uo pipefail

BASH_LOG=".claude/hooks/.log/bash.log"
[ ! -f "$BASH_LOG" ] && exit 0

mkdir -p .claude/memory.proposed/skills
CANDIDATES=".claude/memory.proposed/skills/_candidates.jsonl"
TODAY=$(date +%Y-%m-%d)
COUNTER=".claude/memory/.cache/sig-detector-count-${TODAY}"
mkdir -p "$(dirname "$COUNTER")"

# JUSTIFIED: cat error output discarded and the fallback 0 covers it — a missing counter file means no candidates emitted today yet, so 0 is the correct seed
today_count=$(cat "$COUNTER" 2>/dev/null || echo 0)
[ "$today_count" -ge 5 ] && exit 0

# Gap-audit G18: the header's quality gates are now implemented, portably
# (no gawk mktime). Last 200 lines INCLUDING failures (the exit-0 ratio needs
# them); session id increments on a >1h timestamp gap; a trigram qualifies on
# count ≥5 AND ≥2 distinct sessions AND ≥80% of instances fully exit-0.
recent=$(tail -200 "$BASH_LOG")
[ -z "$recent" ] && exit 0

# Emits qualifying signatures "fam1||fam2||fam3". Timestamp → approximate
# minutes via fixed 31-day months — exact gaps don't matter, only ">60min".
qualifying=$(echo "$recent" | awk -F'\t' '
  function tmins(ts,    y, mo, d, h, mi) {
    y  = substr(ts, 1, 4) + 0; mo = substr(ts, 6, 2) + 0
    d  = substr(ts, 9, 2) + 0; h  = substr(ts, 12, 2) + 0
    mi = substr(ts, 15, 2) + 0
    return ((((y * 12 + mo) * 31 + d) * 24 + h) * 60 + mi)
  }
  {
    t = tmins($1)
    if (NR > 1 && t - prev_t > 60) session++
    prev_t = t
    split($3, parts, " ")
    fam[NR] = parts[1] " " parts[2]
    ok[NR] = ($2 == "exit=0") ? 1 : 0
    sess[NR] = session + 0
  }
  END {
    for (i = 1; i <= NR - 2; i++) {
      if (fam[i] == "" || fam[i+1] == "" || fam[i+2] == "") continue
      sig = fam[i] "||" fam[i+1] "||" fam[i+2]
      count[sig]++
      if (ok[i] && ok[i+1] && ok[i+2]) clean[sig]++
      sessions[sig, sess[i]] = 1
    }
    for (sig in count) {
      if (count[sig] < 5) continue
      nsess = 0
      for (k in sessions) { split(k, p, SUBSEP); if (p[1] == sig) nsess++ }
      if (nsess < 2) continue
      if ((clean[sig] + 0) / count[sig] < 0.8) continue
      print count[sig] "\t" sig
    }
  }
' | sort -rn | cut -f2)
[ -z "$qualifying" ] && exit 0

emitted=0
while IFS= read -r sig; do
  [ -z "$sig" ] && continue
  # Hash the signature
  # JUSTIFIED: md5 error output discarded — BSD `md5` is absent on Linux, so we fall through to `md5sum`; the chain ends with a 0 literal so a hash is always produced
  sig_hash=$(printf '%s' "$sig" | md5 2>/dev/null || printf '%s' "$sig" | md5sum | cut -d' ' -f1 || echo "0")
  sig_hash="${sig_hash:0:8}"

  # Skip if already a candidate today
  # JUSTIFIED: grep error output discarded — a non-match (this signature is new today) is the normal case and correctly proceeds to emit
  if [ -f "$CANDIDATES" ] && grep -q "\"sig_hash\":\"$sig_hash\"" "$CANDIDATES" 2>/dev/null; then
    continue
  fi

  # Derive a slug suggestion from the first family
  fam1=$(echo "$sig" | cut -d'|' -f1 | tr -s ' ' '-' | tr -d '[:punct:]' | tr '[:upper:]' '[:lower:]')
  slug_suggestion=$(echo "$fam1" | head -c 24)-$(echo "$sig_hash" | head -c 6)

  # Emit candidate.
  # JUSTIFIED: jq error output discarded — appending a candidate is best-effort in
  # this Stop hook; a write hiccup must not fail the stop, the counter just stays put.
  # (Gap-audit G18 bonus fix: this comment previously sat INSIDE the single-quoted
  # jq program — its apostrophes broke the shell quoting and every emit silently
  # failed, which is why _candidates.jsonl never accumulated anything.)
  jq -nc \
    --arg ts "$(date -Iseconds)" \
    --arg sig "$sig" \
    --arg hash "$sig_hash" \
    --arg slug "$slug_suggestion" \
    '{
      ts: $ts,
      sig: $sig,
      sig_hash: $hash,
      suggested_slug: $slug,
      source: "task-signature-detector"
    }' >> "$CANDIDATES" 2>/dev/null

  emitted=$((emitted + 1))
  [ "$emitted" -ge 2 ] && break  # one signal per hook fire
done <<< "$qualifying"

if [ "$emitted" -gt 0 ]; then
  echo $((today_count + emitted)) > "$COUNTER"
fi

exit 0
