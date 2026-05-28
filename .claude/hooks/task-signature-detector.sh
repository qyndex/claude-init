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

today_count=$(cat "$COUNTER" 2>/dev/null || echo 0)
[ "$today_count" -ge 5 ] && exit 0

# Read last 200 successful (exit=0) bash log lines
recent=$(tail -200 "$BASH_LOG" | grep -E 'exit=0' | head -200)
[ -z "$recent" ] && exit 0

# Extract command families: first token after the timestamp+exit
# Example log line: 2026-05-28T01:02:03+10:00\texit=0\tnpm install foo
# Family = "npm install" (first 2 tokens of the command)
families=$(echo "$recent" | awk -F'\t' '{
  # $3 is the command; take first 2 tokens
  split($3, parts, " ")
  print parts[1] " " parts[2]
}' | head -200)

# Build 3-gram signatures (sliding window over consecutive families)
trigrams=$(echo "$families" | awk '
  {
    history[NR] = $0
  }
  END {
    for (i = 1; i <= NR - 2; i++) {
      # Skip if any family is empty
      if (history[i] == "" || history[i+1] == "" || history[i+2] == "") continue
      printf "%s||%s||%s\n", history[i], history[i+1], history[i+2]
    }
  }
' | sort | uniq -c | sort -rn)

# Pick trigrams with count ≥ 5
qualifying=$(echo "$trigrams" | awk '$1 >= 5 { sub(/^ *[0-9]+ +/, ""); print }')
[ -z "$qualifying" ] && exit 0

# For each qualifying trigram, check if it appears in ≥ 2 distinct sessions
# Session = bash.log timestamp gap > 1h between consecutive lines
emitted=0
while IFS= read -r sig; do
  [ -z "$sig" ] && continue
  # Hash the signature
  sig_hash=$(printf '%s' "$sig" | md5 2>/dev/null || printf '%s' "$sig" | md5sum | cut -d' ' -f1 || echo "0")
  sig_hash="${sig_hash:0:8}"

  # Skip if already a candidate today
  if [ -f "$CANDIDATES" ] && grep -q "\"sig_hash\":\"$sig_hash\"" "$CANDIDATES" 2>/dev/null; then
    continue
  fi

  # Derive a slug suggestion from the first family
  fam1=$(echo "$sig" | cut -d'|' -f1 | tr -s ' ' '-' | tr -d '[:punct:]' | tr '[:upper:]' '[:lower:]')
  slug_suggestion=$(echo "$fam1" | head -c 24)-$(echo "$sig_hash" | head -c 6)

  # Emit candidate
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
