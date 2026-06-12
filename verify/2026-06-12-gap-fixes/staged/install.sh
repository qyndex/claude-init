#!/usr/bin/env bash
# Consolidated operator install for the 2026-06-12 gap-fix campaign.
#
# These files are constitution-class (.claude/CLAUDE.md, settings.json, hooks,
# agents, workflows) — the agent cannot write them; YOU install them.
#
# RUN FROM THE REPO ROOT, in your own shell (or via `! bash ...` in a session):
#   bash verify/2026-06-12-gap-fixes/staged/install.sh
#
# Then re-prove every fix against the live tree:
#   INSTALLED=1 bash verify/2026-06-12-gap-fixes/test-gap-fixes.sh
#   bash .claude/scripts/validate.sh        # the G6 failure clears
#
# INSTALL BEFORE PUSHING — until installed, validate.sh and
# check-model-consistency.sh intentionally fail (enforceability gates pointing
# at the staged fixes), which would fail harness-validate.yml in CI.

set -euo pipefail

[ -f .claude/CLAUDE.md ] || { echo "Run from the repo root."; exit 1; }
STAGED="verify/2026-06-12-gap-fixes/staged"
[ -d "$STAGED" ] || { echo "No $STAGED — nothing to install."; exit 1; }

echo "Installing staged gap fixes into the live tree:"
count=0
while IFS= read -r src; do
  rel="${src#"$STAGED"/}"
  case "$rel" in install.sh) continue ;; esac
  mkdir -p "$(dirname "$rel")"
  cp "$src" "$rel"
  case "$rel" in *.sh) chmod +x "$rel" ;; esac
  echo "  ✓ $rel"
  count=$((count + 1))
done < <(find "$STAGED" -type f | sort)

echo
echo "$count file(s) installed."
echo "Next:"
echo "  INSTALLED=1 bash verify/2026-06-12-gap-fixes/test-gap-fixes.sh   # re-prove (expect 164/164)"
echo "  bash .claude/scripts/validate.sh                                 # expect 0 failures"
echo "  bash .claude/scripts/check-model-consistency.sh                  # cross-model gate green"
