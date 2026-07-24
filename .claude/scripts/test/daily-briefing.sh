#!/usr/bin/env bash
# Tests daily-briefing.sh — the morning digest. The operator directive: every
# shipped claim must attach a VERIFIABLE artifact as proof (evidence verdict, TDD
# ledger, STATE phase). These tests assert the proof is present, and that an
# unbacked claim is marked ⚠ UNPROVEN rather than asserted.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
SCRIPT="$ROOT/.claude/scripts/daily-briefing.sh"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
outdir="$tmp/briefings"

# A ship-log with one PR carrying a REAL evidence path (spec 004 PASS bundle) and
# one spec WITHOUT evidence (to exercise the UNPROVEN path).
ev_real="verify/2026-07-23-spec004-reconcile/evidence.json"
cat > "$tmp/ship-log.jsonl" <<EOF
{"pr":22,"title":"feat: revive metabolism","mergedAt":"2026-07-23T23:36:39Z","mergeCommit":"0d770c017dce","url":"https://github.com/qyndex/claude-init/pull/22","specs":["004","999"],"tasks":[],"initiatives":[],"evidence":["$ev_real"],"decisions":["Constraint:    x guarded → patch","Directive:     operator autonomous-ship"]}
EOF

run() { BRIEF_SHIP_LOG="$tmp/ship-log.jsonl" BRIEF_OUT_DIR="$outdir" BRIEF_NO_GH=1 bash "$SCRIPT" "$@"; }

# (1) Writes a dated briefing file for the merge date.
run --date 2026-07-23 --no-commit >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ]; check "briefing exits 0" $?
out="$outdir/2026-07-23.md"
[ -f "$out" ]; check "writes docs/briefings/<date>.md" $?

# (2) Lists the shipped PR with its merge SHA + URL (the PR proof).
grep -q 'PR #22' "$out"; check "briefing names the shipped PR #22" $?
grep -q '0d770c017dce' "$out"; check "briefing cites the merge commit SHA (proof)" $?
grep -q 'pull/22' "$out"; check "briefing links the PR URL" $?

# (3) THE KEY REQUIREMENT: a spec with evidence shows the verdict inline (proof),
#     quoted from the real evidence.json (not asserted).
grep -qE 'spec 004' "$out"; check "briefing lists spec 004" $?
grep -qE 'verdict=PASS ac_proven=18/18' "$out"; check "spec 004 shows evidence.json verdict INLINE (verifiable proof)" $?
grep -q "$ev_real" "$out"; check "spec 004 links the evidence.json path" $?

# (4) A spec WITHOUT evidence is flagged UNPROVEN, not silently claimed shipped.
grep -qE 'spec 999.*|999' "$out" && grep -qi 'UNPROVEN' "$out"; check "spec 999 (no evidence) is marked ⚠ UNPROVEN" $?

# (5) Decisions from the record are surfaced.
grep -qi 'Directive:.*autonomous-ship' "$out"; check "briefing surfaces the key decisions" $?

# (6) Proof policy statement is present (the guarantee).
grep -qi 'no artifact\|UNPROVEN.*§VII' "$out"; check "briefing states the proof policy (§VII.8)" $?

# (7) A date with NO merges writes an honest 'nothing shipped', not silence.
run --date 2099-01-01 --no-commit >/dev/null 2>&1
grep -qi 'Nothing shipped' "$outdir/2099-01-01.md"; check "empty day → honest 'nothing shipped' briefing" $?

# (8) Missing ship-log → still writes a briefing (no crash).
out2=$(BRIEF_SHIP_LOG="$tmp/nope.jsonl" BRIEF_OUT_DIR="$tmp/b2" BRIEF_NO_GH=1 bash "$SCRIPT" --date 2026-07-23 --no-commit 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ -f "$tmp/b2/2026-07-23.md" ]; check "absent ship-log → briefing still written, no crash" $?

echo "passed: $pass"; echo "failed: $fail"
[ "$fail" -eq 0 ]
