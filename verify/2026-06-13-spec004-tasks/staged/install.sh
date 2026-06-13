#!/usr/bin/env bash
# spec 004 staged install — operator-run. The hook + workflow files are
# constitution-class (pre-edit-constitution-guard.sh), so agent writes are
# blocked by design; these fixes are staged here for you to apply.
#
#   bash verify/2026-06-13-spec004-tasks/staged/install.sh          # dry-run (diffs)
#   APPLY=1 bash verify/2026-06-13-spec004-tasks/staged/install.sh  # install into this repo
#   APPLY=1 TARGETS="/path/to/other-repo" bash .../install.sh       # also install elsewhere (e.g. the e2e sandbox)
#
# What this installs (all spec 004):
#   .claude/hooks/pre-edit-constitution-guard.sh  T-132 SC2295 — quote $ROOT in prefix-strip (security guard)
#   .claude/hooks/pre-edit-legacy-guard.sh        T-132 SC2295 — same
#   .claude/hooks/pre-bash-dep-freshness.sh       T-132 SC2295 — quote $ephemeral in prefix-strip
#   .claude/hooks/session-end.sh                  T-132 SC1083 — quote git '@{u}..HEAD' revspec
#   .claude/hooks/session-start-context.sh        T-132 SC2034 — wire atlas_sha/current_sha into the staleness check (was dead)
#   .github/workflows/commitlint.yml              T-135 — drop --extends so commitlint.config.js is read
#   .github/workflows/merge-gate.yml              T-134 — fix gh json field htmlUrl->url; repo createdAt for the age window
#   .github/workflows/claude-review.yml           FINDING-14 — add id-token: write (claude-code-action OIDC auth)
#   .github/workflows/pr-review.yml               FINDING-14 — same
#   .github/workflows/daily-batch.yml             FINDING-16 — osv-scanner reusable workflow at job level (was an invalid step; broke parse)
#
# NOT installed by this script (already applied, agent-writable, in the main commit):
#   .shellcheckrc, commitlint.config.js, lint-silent-failures.sh ratchet +
#   silent-failure-baseline.json, audit-doc-claims.sh fix.
#
# Also paste TASKS-append.md into tasks/TASKS.md (constitution-class) by hand.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../../.." && pwd)"
rels="
.claude/hooks/pre-edit-constitution-guard.sh
.claude/hooks/pre-edit-legacy-guard.sh
.claude/hooks/pre-bash-dep-freshness.sh
.claude/hooks/session-end.sh
.claude/hooks/session-start-context.sh
.github/workflows/commitlint.yml
.github/workflows/merge-gate.yml
.github/workflows/claude-review.yml
.github/workflows/pr-review.yml
.github/workflows/daily-batch.yml
"

install_into() {
  local target="$1" rel src dst
  for rel in $rels; do
    src="$here/$rel"; dst="$target/$rel"
    if [ "${APPLY:-0}" = "1" ]; then
      cp "$src" "$dst"
      case "$rel" in .claude/hooks/*.sh) chmod +x "$dst" ;; esac
      echo "installed: $dst"
    else
      echo "── diff vs $dst ──"
      diff -u "$dst" "$src" || true
    fi
  done
}

install_into "$repo_root"
for t in ${TARGETS:-}; do install_into "$t"; done

if [ "${APPLY:-0}" = "1" ]; then
  echo
  echo "Done. Now: paste TASKS-append.md into tasks/TASKS.md, then run:"
  echo "  bash .claude/scripts/validate.sh && shellcheck --format=gcc .claude/hooks/*.sh"
else
  echo
  echo "Dry-run only. Re-run with APPLY=1 to install."
fi
