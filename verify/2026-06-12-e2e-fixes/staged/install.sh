#!/usr/bin/env bash
# OPERATOR-ONLY installer for the 2026-06-12 e2e-audit fix campaign.
#
# Copies every staged constitution-class file over its live counterpart.
# These files are write-protected from Claude sessions (pre-edit-constitution-guard.sh),
# so the campaign staged its fixes here for a HUMAN to install.
#
# After install: bash .claude/scripts/validate.sh should drop from 12 by-design
# pre-install failures to 0 (plus 2 environment warnings). Run the campaign rig
# in installed mode to prove it:
#   INSTALLED=1 bash verify/2026-06-12-e2e-fixes/test-e2e-fixes.sh
#
# Usage (from repo root):
#   bash verify/2026-06-12-e2e-fixes/staged/install.sh           # dry-run (default)
#   APPLY=1 bash verify/2026-06-12-e2e-fixes/staged/install.sh   # actually install

set -uo pipefail
SG="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SG/../../.." && pwd)"
cd "$ROOT"

APPLY="${APPLY:-0}"
n=0
echo "Staged → live ($([ "$APPLY" = 1 ] && echo APPLYING || echo DRY-RUN)):"
while IFS= read -r src; do
  rel="${src#"$SG"/}"
  case "$rel" in install.sh) continue ;; esac
  dst="$ROOT/$rel"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    continue  # already identical
  fi
  n=$((n+1))
  printf '  %-60s %s\n' "$rel" "$([ -f "$dst" ] && echo '(overwrite)' || echo '(new)')"
  if [ "$APPLY" = 1 ]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    case "$rel" in *.sh) chmod +x "$dst" ;; esac
  fi
done < <(find "$SG" -type f ! -name install.sh | sort)

echo
if [ "$APPLY" = 1 ]; then
  echo "$n file(s) installed. Now run:"
  echo "  bash .claude/scripts/validate.sh"
  echo "  INSTALLED=1 bash verify/2026-06-12-e2e-fixes/test-e2e-fixes.sh"
else
  echo "$n file(s) differ and would be installed. Re-run with APPLY=1 to install."
fi
