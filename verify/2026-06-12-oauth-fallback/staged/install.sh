#!/usr/bin/env bash
# oauth-fallback staged install — operator-run (workflow files are
# constitution-class, agent writes are blocked by design).
#
#   bash verify/2026-06-12-oauth-fallback/staged/install.sh            # dry-run (diffs)
#   APPLY=1 bash verify/2026-06-12-oauth-fallback/staged/install.sh   # install into this repo
#   APPLY=1 TARGETS="/path/to/other-repo" bash .../install.sh         # also install elsewhere (e.g. the e2e sandbox)
#
# What this changes:
#   claude-review.yml  — preflight accepts CLAUDE_CODE_OAUTH_TOKEN or
#                        ANTHROPIC_API_KEY; passes claude_code_oauth_token
#                        to claude-code-action@v1
#   pr-review.yml      — passes claude_code_oauth_token alongside the API key
#   claude-security.yml— BUG FIX: input renamed anthropic_api_key →
#                        claude-api-key (the only input the pinned
#                        claude-code-security-review SHA declares); preflight
#                        message states OAuth tokens are NOT accepted here
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../../.." && pwd)"
files="claude-review.yml pr-review.yml claude-security.yml"

install_into() {
  local target="$1"
  for f in $files; do
    local src="$here/.github/workflows/$f" dst="$target/.github/workflows/$f"
    if [ "${APPLY:-0}" = "1" ]; then
      cp "$src" "$dst"
      echo "installed: $dst"
    else
      echo "── diff vs $dst ──"
      diff -u "$dst" "$src" || true
    fi
  done
}

install_into "$repo_root"
for t in ${TARGETS:-}; do install_into "$t"; done

[ "${APPLY:-0}" = "1" ] || echo
[ "${APPLY:-0}" = "1" ] && echo "Done. Verify: bash .claude/scripts/validate.sh" \
  || echo "Dry-run only. Re-run with APPLY=1 to install."
