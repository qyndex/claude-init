#!/usr/bin/env bash
# Integration coverage enforcement — Round 8 D.
#
# For every changed file matching routes/handlers/api/, require a
# corresponding *.integration.test.* file. Same for files matching
# repositories/dao/queries/ — they need testcontainers integration tests.
#
# Exit 1 if any changed handler/query lacks an integration test.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

BASE="${1:-main}"

# JUSTIFIED: git diff error output discarded — when BASE is unknown (e.g. shallow clone) we fall back to git ls-files so the whole tree is checked rather than aborting
changed=$(git diff --name-only "$BASE...HEAD" 2>/dev/null || git ls-files)
[ -z "$changed" ] && { echo "no changes"; exit 0; }

missing=0
api_changed=0
db_changed=0

for f in $changed; do
  [ -f "$f" ] || continue

  # Skip non-source
  case "$f" in
    *.test.*|*.spec.*|*/tests/*|*/test/*|*/__tests__/*) continue ;;
  esac

  # API handlers / routes
  if echo "$f" | grep -qE '/(routes|handlers|api|controllers)/'; then
    api_changed=$((api_changed + 1))
    base=$(basename "$f" | sed -E 's/\.[a-z]+$//')
    # Look for *.integration.test.* anywhere in the repo
    # JUSTIFIED: find error output discarded — permission-denied subtrees are skipped; grep -q decides presence, and "no match" correctly flags the missing test
    if ! find . -name "${base}.integration.test.*" -not -path '*/node_modules/*' -print -quit 2>/dev/null | grep -q .; then
      echo "  ✗ API file $f lacks ${base}.integration.test.*"
      missing=$((missing + 1))
    fi
  fi

  # DB queries / repos
  if echo "$f" | grep -qE '/(repositories|dao|queries|repos)/'; then
    db_changed=$((db_changed + 1))
    base=$(basename "$f" | sed -E 's/\.[a-z]+$//')
    # JUSTIFIED: find error output discarded — permission-denied subtrees are skipped; grep -q decides presence, and "no match" correctly flags the missing test
    if ! find . -name "${base}.integration.test.*" -not -path '*/node_modules/*' -print -quit 2>/dev/null | grep -q .; then
      echo "  ✗ DB file $f lacks ${base}.integration.test.*"
      missing=$((missing + 1))
    fi
  fi
done

if [ "$missing" -gt 0 ]; then
  echo
  echo "✗ $missing changed file(s) lack integration tests."
  echo "  Conventions:"
  echo "    - Files in /routes|/handlers|/api|/controllers → *.integration.test.{ts,py,go,rs}"
  echo "    - Files in /repositories|/dao|/queries → testcontainers-backed test"
  echo "  Add the missing tests; the implementer agent should write them under TDD."
  exit 1
fi

echo "✓ Integration coverage check passed (API changes: $api_changed, DB changes: $db_changed)"
