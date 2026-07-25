#!/usr/bin/env bash
# Tests reconcile-shipped.sh — the on-merge status-flip + ship-log recorder.
# Driven by a fixture merged-PR JSON (RECON_MERGED_JSON) so no gh/network.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
SCRIPT="$ROOT/.claude/scripts/reconcile-shipped.sh"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
statedir="$tmp/state"

cat > "$tmp/merged.json" <<'EOF'
[{"number":22,"title":"feat: revive metabolism","mergedAt":"2026-07-23T23:36:39Z","mergeCommit":{"oid":"0d770c017dcef0f89a978068ba952f5e093ef9c7"},"url":"https://github.com/qyndex/claude-init/pull/22","headRefName":"harness/x"}]
EOF

run() { RECON_MERGED_JSON="$tmp/merged.json" RECON_STATE_DIR="$statedir" bash "$SCRIPT" "$@"; }

# (1) Produces a valid JSONL ship-log record for the merged PR.
run >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ]; check "reconcile exits 0 on a merged PR" $?
[ -f "$statedir/ship-log.jsonl" ]; check "writes .claude/state/ship-log.jsonl" $?
# Each line must be valid JSON with the required proof fields.
line=$(head -1 "$statedir/ship-log.jsonl" 2>/dev/null)
printf '%s' "$line" | jq -e '.pr and .mergeCommit and (.evidence|type=="array") and (.decisions|type=="array") and (.specs|type=="array")' >/dev/null 2>&1
check "record carries pr, mergeCommit, evidence[], decisions[], specs[] (proof fields)" $?

# (2) Evidence array points at real evidence.json bundles (the PROOF, not a claim).
ev=$(printf '%s' "$line" | jq -r '.evidence[]?' | head -1)
[ -n "$ev" ] && [ -f "$ev" ]; check "evidence[] path resolves to a real evidence.json on disk" $?

# (3) Decisions array captures commit trailers from the merge commit.
printf '%s' "$line" | jq -e '[.decisions[] | select(test("Constraint:|Directive:"))] | length > 0' >/dev/null 2>&1
check "decisions[] pulls Constraint/Directive trailers from the merge commit" $?

# (4) Idempotent — a second run does NOT duplicate the record.
before=$(wc -l < "$statedir/ship-log.jsonl")
run >/dev/null 2>&1
after=$(wc -l < "$statedir/ship-log.jsonl")
[ "$before" -eq "$after" ]; check "second run does not duplicate the PR record (dedupe by pr#)" $?

# (5) Watermark advances so the next run skips already-seen merges.
[ -f "$statedir/.reconcile-watermark" ]; check "advances the merge watermark" $?
wm=$(cat "$statedir/.reconcile-watermark" 2>/dev/null)
[ "$wm" = "2026-07-23T23:36:39Z" ]; check "watermark = newest mergedAt" $?

# (6) --since filters out older merges (nothing to do).
out=$(RECON_MERGED_JSON="$tmp/merged.json" RECON_STATE_DIR="$tmp/state2" bash "$SCRIPT" --since 2026-08-01T00:00:00Z 2>&1)
printf '%s' "$out" | grep -qi 'no newly-merged'; check "--since after the merge → nothing to reconcile" $?

# (7) Empty merged list → clean exit, no crash, no bogus record.
echo '[]' > "$tmp/empty.json"
out=$(RECON_MERGED_JSON="$tmp/empty.json" RECON_STATE_DIR="$tmp/state3" bash "$SCRIPT" 2>&1); rc=$?
[ "$rc" -eq 0 ]; check "empty merged list exits 0" $?
[ ! -s "$tmp/state3/ship-log.jsonl" ] 2>/dev/null || [ ! -f "$tmp/state3/ship-log.jsonl" ]
check "empty merged list writes no records" $?

echo "passed: $pass"; echo "failed: $fail"
[ "$fail" -eq 0 ]
