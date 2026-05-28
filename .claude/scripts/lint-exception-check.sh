#!/usr/bin/env bash
# Lint-exception audit — Round 8 E.
#
# Scans diff for lint/type disables; requires JUSTIFICATION: + ISSUE: markers
# within 3 lines. Used by both the GitHub workflow and local-pr-check.sh.
#
# Usage: bash lint-exception-check.sh <base-sha> <head-sha>
#        bash lint-exception-check.sh               # diff vs main

set -uo pipefail

BASE="${1:-main}"
HEAD="${2:-HEAD}"

# Known disable patterns (matches conventions.yml)
patterns='eslint-disable|@ts-ignore|@ts-expect-error|@ts-nocheck|# noqa|# type: ignore|# nosec|# pragma: no cover|#\[allow\(|//[[:space:]]*nolint|//nolint:|//gocover:ignore|LINT-DISABLE-OK'

# Files changed in the diff
# JUSTIFIED: git stderr suppressed — an unresolvable BASE/HEAD ref yields no files; the [ -z "$files" ] guard below treats that as "nothing changed" and exits 0
files=$(git diff --name-only "$BASE...$HEAD" -- '*.ts' '*.tsx' '*.js' '*.jsx' '*.py' '*.rs' '*.go' '*.java' 2>/dev/null)

if [ -z "$files" ]; then
  echo "✓ No source files changed"
  exit 0
fi

# Find new disable lines (lines starting with + that match patterns)
# JUSTIFIED: git stderr + grep non-match suppressed — no added disable lines makes the grep exit 1; empty $new_disables is the clean case, handled by [ -z "$new_disables" ] below
new_disables=$(git diff "$BASE...$HEAD" -- '*.ts' '*.tsx' '*.js' '*.jsx' '*.py' '*.rs' '*.go' '*.java' 2>/dev/null \
  | grep -E "^\+[^+]" \
  | grep -E "$patterns" || true)

if [ -z "$new_disables" ]; then
  echo "✓ No new lint disables in diff"
  exit 0
fi

echo "→ Found disables in diff; checking for JUSTIFICATION + ISSUE markers"
echo

issues=0
for f in $files; do
  [ -f "$f" ] || continue

  awk -v file="$f" -v pat="$patterns" '
    {
      lines[NR] = $0
    }
    END {
      for (i = 1; i <= NR; i++) {
        if (match(lines[i], pat)) {
          has_justif = 0; has_issue = 0
          for (j = i - 3; j <= i + 3; j++) {
            if (j < 1 || j > NR) continue
            if (match(lines[j], /JUSTIFICATION[: ]/)) has_justif = 1
            if (match(lines[j], /ISSUE[: ]+#?[0-9]+/)) has_issue = 1
          }
          if (!has_justif || !has_issue) {
            missing = ""
            if (!has_justif) missing = "JUSTIFICATION"
            if (!has_issue) missing = (missing ? missing " + " : "") "ISSUE"
            printf "  ✗ %s:%d — missing %s marker\n", file, i, missing
            exit 1
          }
        }
      }
      exit 0
    }
  ' "$f" || issues=$((issues + 1))
done

if [ "$issues" -gt 0 ]; then
  echo
  echo "✗ $issues file(s) have un-justified disables."
  echo "  Add inline comments (within 3 lines of the disable):"
  echo "    // JUSTIFICATION: <why this disable is necessary>"
  echo "    // ISSUE: #<github issue number tracking removal>"
  echo
  echo "  Security disables (# nosec, # noqa: S*, security-*) also need an ADR in .claude/memory/decisions/"
  exit 1
fi

echo
echo "✓ All disables have JUSTIFICATION + ISSUE markers"
