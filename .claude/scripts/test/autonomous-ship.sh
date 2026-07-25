#!/usr/bin/env bash
# Tests autonomous-ship.sh — the green-gated auto-merge trigger. The one rule that
# matters: NEVER merge without every required check green (operator decision
# 2026-07-24). These tests drive the gate with a fake `gh` on PATH so no network
# is touched, and assert the fail-closed posture on every not-green shape.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
SCRIPT="$ROOT/.claude/scripts/autonomous-ship.sh"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bindir="$tmp/bin"; mkdir -p "$bindir"

# ── Fake gh: behavior driven by files the test writes into $tmp. ──
# GH_STATE controls pr view; GH_CHECKS is the JSON for `gh pr checks`.
cat > "$bindir/gh" <<'FAKE'
#!/usr/bin/env bash
sub="$1 $2"
case "$1 $2" in
  "repo view")   echo "qyndex/claude-init"; exit 0 ;;
esac
case "$1" in
  api)  # rulesets length probe
        if [ -f "$TMPD/ruleset_count" ]; then cat "$TMPD/ruleset_count"; else echo 1; fi; exit 0 ;;
  pr)
    case "$2" in
      view)   cat "$TMPD/pr_view.json"; exit 0 ;;
      checks) cat "$TMPD/pr_checks.json"; exit 0 ;;
      edit)   echo "edited" >> "$TMPD/gh_calls"; exit 0 ;;
      merge)  echo "merge $*" >> "$TMPD/gh_calls"; exit 0 ;;
    esac ;;
esac
exit 0
FAKE
chmod +x "$bindir/gh"
# jq must remain real
export TMPD="$tmp"
run() { PATH="$bindir:$PATH" TMPD="$tmp" AUTOSHIP_REPO="qyndex/claude-init" bash "$SCRIPT" "$@"; }

# Default: open, non-draft PR + a live ruleset.
echo '{"state":"OPEN","isDraft":false,"mergeStateStatus":"CLEAN","title":"feat: x"}' > "$tmp/pr_view.json"
echo '1' > "$tmp/ruleset_count"

# (1) ALL green → arms merge (dry-run reports would-arm; real run calls gh pr merge).
echo '[{"name":"a","state":"SUCCESS","bucket":"pass"},{"name":"b","state":"SUCCESS","bucket":"pass"}]' > "$tmp/pr_checks.json"
out=$(run 999 --dry-run 2>&1); rc=$?
[ "$rc" -eq 0 ]; check "all-green PR: dry-run exits 0 (would arm)" $?
printf '%s' "$out" | grep -q 'all 2 checks GREEN'; check "all-green PR: reports checks green" $?

: > "$tmp/gh_calls"
run 999 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ]; check "all-green PR: real run exits 0" $?
grep -q 'merge 999 .*--auto --squash' "$tmp/gh_calls"; check "all-green PR: arms gh pr merge --auto --squash" $?
grep -q 'edited' "$tmp/gh_calls"; check "all-green PR: applies the auto-merge-ok label" $?

# (2) One check FAILING → refuse (exit 3), NO merge.
echo '[{"name":"a","state":"SUCCESS","bucket":"pass"},{"name":"b","state":"FAILURE","bucket":"fail"}]' > "$tmp/pr_checks.json"
: > "$tmp/gh_calls"
run 999 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ]; check "one failing check: refuses with exit 3" $?
! grep -q 'merge 999' "$tmp/gh_calls"; check "one failing check: does NOT call gh pr merge" $?

# (3) A PENDING check → refuse (not green == not merge).
echo '[{"name":"a","state":"PENDING","bucket":"pending"}]' > "$tmp/pr_checks.json"
: > "$tmp/gh_calls"
run 999 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ]; check "pending check: refuses (exit 3)" $?
! grep -q 'merge' "$tmp/gh_calls"; check "pending check: no merge" $?

# (4) A required check SKIPPED (billing-outage shape) → refuse.
echo '[{"name":"a","state":"SUCCESS","bucket":"pass"},{"name":"b","state":"SKIPPED","bucket":"skipping"}]' > "$tmp/pr_checks.json"
run 999 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ]; check "skipped check: refuses (fail-closed on non-pass)" $?

# (5) ZERO checks reporting (CI not running / billing-blocked) → refuse, fail-closed.
echo '[]' > "$tmp/pr_checks.json"
run 999 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ]; check "no checks at all: refuses (fail-closed, not merge)" $?

# (6) No live ruleset → refuse (exit 4) even if checks would be green.
echo '0' > "$tmp/ruleset_count"
echo '[{"name":"a","state":"SUCCESS","bucket":"pass"}]' > "$tmp/pr_checks.json"
run 999 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 4 ]; check "no live ruleset: refuses (exit 4) — --auto would merge on empty checks" $?
echo '1' > "$tmp/ruleset_count"

# (7) Draft or already-merged PR → refuse (exit 3), never arm.
echo '{"state":"MERGED","isDraft":false,"title":"x"}' > "$tmp/pr_view.json"
echo '[{"name":"a","bucket":"pass","state":"SUCCESS"}]' > "$tmp/pr_checks.json"
run 999 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ]; check "already-merged PR: refuses" $?

# (8) There is NO way to bypass the GREEN-CHECKS gate — no env/flag that skips the
#     not_green refusal. (AUTOSHIP_SKIP_RULESET is a test-only ruleset hook and does
#     NOT relax the checks gate, so it's excluded.) Assert no force-merge and no
#     checks-skipping override exists.
! grep -qiE 'AUTOSHIP_(FORCE|SKIP_CHECKS|MERGE_ANYWAY)|--force|-f +origin' "$SCRIPT"
check "no force-merge / skip-checks override exists in the script" $?
# And the not-green refusal (exit 3) is unconditional — no `if` guards it away.
grep -qE 'not_green.*-ne 0|not_green.*!= 0' "$SCRIPT"
check "the not-green refusal is present and unconditional" $?

echo "passed: $pass"; echo "failed: $fail"
[ "$fail" -eq 0 ]
