#!/usr/bin/env bash
# apply-memory-patches.sh — install the guarded-file patches for the memory plan.
#
# The constitution guard (pre-edit-constitution-guard.sh) blocks the agent from
# writing .claude/hooks|skills|settings|agents|rules and .github/workflows, so the
# hook/skill/settings halves of the memory-implementation plan ship as staged
# patches under .claude/memory.proposed/patches/. Run THIS in your own shell to
# apply them (you are not the agent, so the guard does not gate you).
#
# Safe to re-run: each patch is dry-run --check'd first; already-applied patches
# are detected (reverse-check) and skipped, not double-applied.
#
# Usage:
#   bash apply-memory-patches.sh            # apply all
#   bash apply-memory-patches.sh --check    # dry-run only, apply nothing
#   PATCH_DIR=other/dir bash apply-memory-patches.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

PATCH_DIR="${PATCH_DIR:-.claude/memory.proposed/patches}"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

command -v git >/dev/null 2>&1 || { echo "error: git not found"; exit 1; }
[ -d "$PATCH_DIR" ] || { echo "error: no patch dir at $PATCH_DIR"; exit 1; }

shopt -s nullglob
patches=( "$PATCH_DIR"/*.patch )
shopt -u nullglob
[ "${#patches[@]}" -gt 0 ] || { echo "error: no *.patch files in $PATCH_DIR"; exit 1; }

echo "Patch dir : $PATCH_DIR"
echo "Found     : ${#patches[@]} patches"
echo "Mode      : $([ "$CHECK_ONLY" = 1 ] && echo 'DRY-RUN (--check)' || echo 'APPLY')"
echo "─────────────────────────────────────────────"

applied=0 skipped=0 failed=0
failed_list=""

for p in "${patches[@]}"; do
  name="$(basename "$p")"

  # Already applied? A clean REVERSE apply means the change is present.
  if git apply --reverse --check "$p" >/dev/null 2>&1; then
    printf '  ⏭  %-52s already applied — skip\n' "$name"
    skipped=$((skipped+1))
    continue
  fi

  # Forward dry-run: will it apply cleanly to the current tree?
  if ! git apply --check "$p" >/dev/null 2>&1; then
    printf '  ✗  %-52s DOES NOT APPLY\n' "$name"
    echo "     └─ git apply --check output:"
    git apply --check "$p" 2>&1 | sed 's/^/        /'
    failed=$((failed+1))
    failed_list="$failed_list $name"
    continue
  fi

  if [ "$CHECK_ONLY" = 1 ]; then
    printf '  ✓  %-52s would apply cleanly\n' "$name"
    applied=$((applied+1))
    continue
  fi

  if git apply "$p"; then
    printf '  ✓  %-52s applied\n' "$name"
    applied=$((applied+1))
  else
    printf '  ✗  %-52s apply FAILED after passing --check\n' "$name"
    failed=$((failed+1))
    failed_list="$failed_list $name"
  fi
done

echo "─────────────────────────────────────────────"
if [ "$CHECK_ONLY" = 1 ]; then
  echo "dry-run: $applied would apply, $skipped already applied, $failed would FAIL"
else
  echo "done: $applied applied, $skipped already applied, $failed FAILED"
fi
[ -n "$failed_list" ] && echo "FAILED:$failed_list"

if [ "$failed" -gt 0 ]; then
  echo
  echo "⚠ Some patches did not apply. Nothing was force-applied. Resolve the"
  echo "  failing patch(es) above, then re-run — applied ones are skipped."
  exit 1
fi

if [ "$CHECK_ONLY" = 1 ]; then
  echo
  echo "All clean. Re-run without --check to apply:  bash apply-memory-patches.sh"
  exit 0
fi

echo
echo "Next:"
echo "  bash .claude/scripts/validate.sh                    # expect rc=0"
echo "  bash .claude/scripts/memory-index.sh rebuild        # keep index committed-fresh"
echo "  git add -A && git commit                            # commit the applied hook/skill/settings changes"
