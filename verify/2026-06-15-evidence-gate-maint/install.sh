#!/usr/bin/env bash
# Operator-run staged install for the evidence-gate harness-maintenance hatch.
#
# .github/workflows/evidence-gate.yml is constitution-class (agent-write-blocked by
# pre-edit-constitution-guard.sh), so the agent stages the corrected file here and a
# human applies it with cp (which bypasses the Write/Edit hook). Run from repo root.
#
#   APPLY=1 bash verify/2026-06-15-evidence-gate-maint/install.sh
#
# Without APPLY=1 it does a dry-run diff and validates the staged file only.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
staged="verify/2026-06-15-evidence-gate-maint/staged/evidence-gate.yml.staged"
target=".github/workflows/evidence-gate.yml"

[ -f "$staged" ] || { echo "✗ staged file missing: $staged" >&2; exit 1; }

echo "→ validating staged YAML"
ruby -ryaml -e "YAML.load_file('$staged')" || { echo "✗ staged YAML invalid" >&2; exit 1; }
if command -v actionlint >/dev/null 2>&1; then
  tmp=".github/workflows/.install-lint.yml"
  cp "$staged" "$tmp"
  out="$(actionlint "$tmp" 2>&1 | grep -vE 'install-lint' || true)"
  rm -f "$tmp"
  [ -z "$out" ] || { echo "✗ actionlint findings:" >&2; echo "$out" >&2; exit 1; }
  echo "  ✓ actionlint clean"
fi

echo "→ diff (target ← staged)"
diff "$target" "$staged" || true

if [ "${APPLY:-0}" = "1" ]; then
  cp "$staged" "$target"
  echo "✓ applied: $target"
  echo "  next: git add $target && commit on a branch + open PR"
else
  echo "(dry-run — re-run with APPLY=1 to install)"
fi
