#!/usr/bin/env bash
# M-10-lock — every memory-plane writer must serialize through ONE shared lock
# (with_lock "memory-plane"), so a backgrounded dream's rebuild can't interleave
# with a live PostToolUse touch and silently drop the just-written entry
# (O-7 CRITICAL-1). Covers memory-index.sh, memory-gc.sh, memory-rollup.sh,
# initiative-state.sh. All four are unguarded scripts → edited directly.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 0; }

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

SCRIPTS="memory-index.sh memory-gc.sh memory-rollup.sh initiative-state.sh"

# (1) All four source the lock primitive.
for s in $SCRIPTS; do
  grep -qE 'lib/with-lock\.sh' ".claude/scripts/$s"
  check "$s sources lib/with-lock.sh" $?
done

# (2) All four use the SINGLE shared lock name "memory-plane" (not per-script names).
for s in $SCRIPTS; do
  grep -qE 'with_lock "memory-plane"' ".claude/scripts/$s"
  check "$s wraps a write in with_lock \"memory-plane\"" $?
done

# (3) Behavioral concurrency test (hermetic temp repo): a rebuild running
#     concurrently with a touch must NOT drop the touched entry. Without the lock
#     the rebuild's truncate-then-rewrite races the touch's read-modify-write.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/scripts/lib" "$tmp/.claude/memory/patterns" "$tmp/.claude/state/locks"
cp .claude/scripts/memory-index.sh "$tmp/.claude/scripts/"
cp .claude/scripts/lib/with-lock.sh "$tmp/.claude/scripts/lib/"

# Seed a handful of memory files so rebuild takes measurable time (widens the race window).
for i in $(seq 1 12); do
  cat > "$tmp/.claude/memory/patterns/p$i.md" <<EOF
---
name: p$i
description: "seed pattern $i"
metadata:
  type: pattern
  status: established
---
# p$i
EOF
done

# The "live write" target — a file touched WHILE rebuild runs. Filename == id
# (memory-index.sh derives id from `basename "$file" .md`), so the assertion below
# greps for "id":"live-entry".
cat > "$tmp/.claude/memory/patterns/live-entry.md" <<'EOF'
---
name: live-entry
description: "written mid-rebuild — must survive"
metadata:
  type: pattern
  status: established
---
# live
EOF

# Build an initial index so touch has something to modify.
( cd "$tmp" && bash .claude/scripts/memory-index.sh rebuild >/dev/null 2>&1 )

# Race: fire a rebuild in the background, and a touch of live.md in the foreground.
( cd "$tmp" && bash .claude/scripts/memory-index.sh rebuild >/dev/null 2>&1 ) &
rebuild_pid=$!
( cd "$tmp" && bash .claude/scripts/memory-index.sh touch .claude/memory/patterns/live-entry.md >/dev/null 2>&1 )
wait "$rebuild_pid" 2>/dev/null || true

# After both settle, the live entry must be present exactly once and the index
# must be valid JSONL (no torn line from an interleaved write).
# grep -c prints 0 AND exits 1 on no match — capture then default, never `|| echo`
# (that double-prints "0\n0" and breaks the integer test).
live_count=$(grep -c '"id":"live-entry"' "$tmp/.claude/memory/index.jsonl" 2>/dev/null) || true
[ "${live_count:-0}" -ge 1 ]
check "live entry survives a concurrent rebuild+touch (not dropped)" $?

# Every line must parse as JSON (a torn write from an unlocked race would fail this).
torn=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  printf '%s' "$line" | jq -e . >/dev/null 2>&1 || torn=$((torn+1))
done < "$tmp/.claude/memory/index.jsonl"
[ "$torn" -eq 0 ]
check "index.jsonl has no torn/invalid lines after the race ($torn bad)" $?

# The lock dir must not be left behind.
[ ! -d "$tmp/.claude/state/locks/memory-plane.lock" ]
check "memory-plane.lock released after the race (no orphan lockdir)" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
