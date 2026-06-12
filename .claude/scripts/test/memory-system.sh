#!/usr/bin/env bash
# Tests for the memory-system implementation (docs/research/memory-system-review.md §7):
# initiative-state.sh, memory-recall.sh, memory-rollup.sh, memory-index.sh fixes.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

pass=0; fail=0
ok()   { echo "  PASS  $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL  $1"; fail=$((fail+1)); }

echo "[initiative-state.sh]"
out=$(bash .claude/scripts/initiative-state.sh sync 2>&1); rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -q '^initiative-state: synced' \
  && ok "sync exits 0 and reports the synced file" || bad "sync (rc=$rc: $out)"

[ -s .claude/state/current-initiative ] && [ -s .claude/state/current-spec ] \
  && ok "pointer files written (current-initiative, current-spec)" \
  || bad "pointer files missing/empty"

state_file=$(ls -t initiatives/active/*.STATE.md 2>/dev/null | head -1)
[ -n "$state_file" ] && grep -q '^\- \*\*phase\*\*:' "$state_file" \
  && grep -q '^\- \*\*tasks\*\*:' "$state_file" \
  && ok "STATE.md has phase + tasks fields" || bad "STATE.md malformed"

lines=$(wc -l < "$state_file" | tr -d ' ')
[ "$lines" -le 60 ] && ok "STATE.md within 60-line cap ($lines)" || bad "STATE.md over cap ($lines)"

# The template line in TASKS.md must never appear as a task
grep -q 'T-NNN' "$state_file" && bad "STATE.md leaked the T-NNN template line" \
  || ok "no T-NNN template leakage"

show=$(bash .claude/scripts/initiative-state.sh show)
[ -n "$show" ] && [ "$(printf '%s\n' "$show" | wc -l | tr -d ' ')" -eq 1 ] \
  && ok "show emits exactly one injection line" || bad "show output wrong: '$show'"

echo "[memory-recall.sh]"
hits=$(bash .claude/scripts/memory-recall.sh --paths "tasks/TASKS.md" --limit 5)
[ -n "$hits" ] && echo "$hits" | grep -q '^\[recall\]' \
  && ok "recall surfaces entries for a known touched path" || bad "no recall for tasks/TASKS.md"

none=$(bash .claude/scripts/memory-recall.sh --paths "zzz/does-not-exist-anywhere" --limit 5 \
  | grep 'matches working set' || true)
[ -z "$none" ] && ok "no working-set match claimed for an unknown path" \
  || bad "false working-set match: $none"

n=$(bash .claude/scripts/memory-recall.sh --paths "tasks/TASKS.md" --limit 2 | wc -l | tr -d ' ')
[ "$n" -le 2 ] && ok "respects --limit ($n ≤ 2)" || bad "limit ignored ($n)"

echo "[memory-rollup.sh]"
out=$(bash .claude/scripts/memory-rollup.sh weekly); rc=$?
wk=$(ls -t .claude/memory/rollups/*-W*.md | head -1)
[ $rc -eq 0 ] && [ -s "$wk" ] && ok "weekly rollup written ($wk)" || bad "weekly failed (rc=$rc)"

lines=$(wc -l < "$wk" | tr -d ' ')
[ "$lines" -le 100 ] && ok "weekly within 100-line cap ($lines)" || bad "weekly over cap ($lines)"

# idempotent: re-run must not error or duplicate
bash .claude/scripts/memory-rollup.sh auto >/dev/null 2>&1 \
  && ok "auto re-run is idempotent" || bad "auto re-run errored"

echo "[memory-index.sh]"
bash .claude/scripts/memory-index.sh rebuild >/dev/null 2>&1
grep -q '"id":"in-flight"' .claude/memory/index.jsonl \
  && bad "runtime in-flight.md leaked into index" || ok "in-flight.md excluded from index"

est=$(jq -rs '[.[] | select(.status == "established")] | length' .claude/memory/index.jsonl)
[ "$est" -ge 15 ] && ok "lifecycle status populated ($est established)" \
  || bad "status population regressed ($est established)"

created=$(jq -rs '[.[] | select(.created != "")] | length' .claude/memory/index.jsonl)
[ "$created" -ge 15 ] && ok "created dates populated ($created)" || bad "created dates missing ($created)"

echo
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
