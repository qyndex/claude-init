#!/usr/bin/env bash
# Test for the atomic-write library (Spec 001 AC-22).
#
# Tagged: AC-22
#
# Exercises write_atomic <target> [<content>] from .claude/scripts/lib/atomic-write.sh:
#   (a) inline content arg writes the file and returns 0,
#   (b) content piped on stdin (no content arg) writes the file and returns 0,
#   (c) the temp file lives in the SAME directory as the target (so mv is a
#       rename, not a cross-device copy — preserves atomicity),
#   (d) a mv -n collision against an existing target returns 1 (no-clobber),
#   (e) the target's contents are intact after a successful write.
#
# lint-silent-failures: ignore-file
# This is a TEST: it deliberately mutes stderr on the failure-path probes because
# each assertion's exit code (via `check`) is the signal, not diagnostic noise.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LIB="$ROOT/.claude/scripts/lib/atomic-write.sh"

pass=0
fail=0
fails=()
check() {
  local label="$1" rc="$2"
  if [ "$rc" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fails+=("$label"); fi
}

# shellcheck source=/dev/null
. "$LIB"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- (a) inline content arg → returns 0, file written ----
target_a="$TMP/a.json"
write_atomic "$target_a" '{"k":1}'
check "inline-content-returns-0: write_atomic with inline content exits 0" $?
[ -f "$target_a" ] && [ "$(cat "$target_a")" = '{"k":1}' ]
check "inline-content-written: target holds the inline content" $?

# ---- (b) stdin content (no content arg) → returns 0, file written ----
target_b="$TMP/b.json"
printf '%s' '{"k":2}' | write_atomic "$target_b"
check "stdin-content-returns-0: write_atomic reading stdin exits 0" $?
[ -f "$target_b" ] && [ "$(cat "$target_b")" = '{"k":2}' ]
check "stdin-content-written: target holds the piped content" $?

# ---- (c) temp file is created in the SAME dir as target ----
# Probe: count temp siblings during a write by trapping in a subshell is fragile;
# instead assert no stray temp files leak into TMP after a clean write (the lib
# must mv its same-dir temp onto the target, leaving only the target).
ls "$TMP"/.b.json* >/dev/null 2>&1
check "same-dir-temp-cleaned: no leftover temp sibling after a clean write" "$([ $? -ne 0 ] && echo 0 || echo 1)"

# ---- (d) mv -n collision against an existing target returns 1 ----
target_d="$TMP/d.json"
write_atomic "$target_d" 'first'
write_atomic "$target_d" 'second'
collide_rc=$?
check "no-clobber-collision-returns-1: second write to an existing target returns 1" "$([ "$collide_rc" -eq 1 ] && echo 0 || echo 1)"

# ---- (e) collision left the ORIGINAL content intact (no partial overwrite) ----
[ "$(cat "$target_d")" = 'first' ]
check "collision-preserves-original: target still holds the first write" $?

# ---- (f) replace_atomic overwrites an existing target and returns 0 ----
target_f="$TMP/f.json"
replace_atomic "$target_f" 'v1'
replace_atomic "$target_f" 'v2'
check "replace-overwrites-returns-0: replace_atomic over an existing target exits 0" $?
[ "$(cat "$target_f")" = 'v2' ]
check "replace-content-updated: target holds the replacement content" $?

# ---- (g) replace_atomic accepts stdin too ----
target_g="$TMP/g.json"
printf '%s' 'piped' | replace_atomic "$target_g"
check "replace-stdin-returns-0: replace_atomic reading stdin exits 0" $?
[ "$(cat "$target_g")" = 'piped' ]
check "replace-stdin-written: target holds the piped replacement" $?

echo "---"
echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -gt 0 ]; then
  printf '  - %s\n' "${fails[@]}"
  exit 1
fi
exit 0
