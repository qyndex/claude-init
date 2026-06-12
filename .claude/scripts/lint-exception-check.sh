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

# ─── Gap-audit G41: security disables require a RESOLVABLE ADR ────────────
# The "needs an ADR" rule above was a hint string only — nothing checked it.
# A security-class disable must carry an `ADR: NNNN` (or ADR-NNNN) marker
# within 3 lines that resolves to a real file in .claude/memory/decisions/,
# OR the same diff must add/modify a decisions/ file.
sec_patterns='# nosec|# noqa:[[:space:]]*S[0-9]|eslint-disable[^\n]*security|//nolint:gosec|#\[allow\([a-z_]*unsafe'

# JUSTIFIED: git stderr suppressed — a missing decisions/ path in the diff just means no ADR rode along; the inline-marker path below still applies
adr_in_diff=$(git diff --name-only "$BASE...$HEAD" -- '.claude/memory/decisions/*.md' 2>/dev/null || true)

new_sec=$(printf '%s\n' "$new_disables" | grep -E "$sec_patterns" || true)
if [ -n "$new_sec" ]; then
  echo "→ Security-class disables in diff; checking for resolvable ADR (G41)"
  for f in $files; do
    [ -f "$f" ] || continue
    grep -nE "$sec_patterns" "$f" 2>/dev/null | while IFS=: read -r ln _rest; do
      # Collect ±3 lines around the disable and look for an ADR marker
      start=$((ln > 3 ? ln - 3 : 1))
      ctx=$(sed -n "${start},$((ln + 3))p" "$f")
      adr_id=$(printf '%s\n' "$ctx" | grep -oE 'ADR[-: ]+#?[0-9]{1,4}' | grep -oE '[0-9]+' | head -1)
      if [ -n "$adr_id" ]; then
        padded=$(printf '%04d' "$((10#$adr_id))")
        if ls .claude/memory/decisions/"${padded}"-*.md >/dev/null 2>&1; then
          continue  # resolvable ADR — OK
        fi
        echo "  ✗ $f:$ln — ADR: $adr_id does not resolve to .claude/memory/decisions/${padded}-*.md"
        echo "SEC_FAIL" >> "${TMPDIR:-/tmp}/.lint-exc-sec.$$"
      elif [ -n "$adr_in_diff" ]; then
        continue  # ADR rides in the same diff — OK
      else
        echo "  ✗ $f:$ln — security disable with no ADR marker and no decisions/ file in diff"
        echo "SEC_FAIL" >> "${TMPDIR:-/tmp}/.lint-exc-sec.$$"
      fi
    done
  done
  if [ -s "${TMPDIR:-/tmp}/.lint-exc-sec.$$" ]; then
    rm -f "${TMPDIR:-/tmp}/.lint-exc-sec.$$"
    issues=$((issues + 1))
    sec_failed=1
  fi
  rm -f "${TMPDIR:-/tmp}/.lint-exc-sec.$$"
fi

if [ "$issues" -gt 0 ]; then
  echo
  echo "✗ $issues file(s) have un-justified disables."
  echo "  Add inline comments (within 3 lines of the disable):"
  echo "    // JUSTIFICATION: <why this disable is necessary>"
  echo "    // ISSUE: #<github issue number tracking removal>"
  if [ "${sec_failed:-0}" = "1" ]; then
    echo
    echo "  Security disables (# nosec, # noqa: S*, eslint-disable*security) REQUIRE a"
    echo "  resolvable ADR: add 'ADR: NNNN' within 3 lines (file must exist in"
    echo "  .claude/memory/decisions/) or ship the ADR in the same diff."
    echo "  Create one: bash .claude/scripts/adr-new.sh \"<title>\" --by human --tags security"
  fi
  exit 1
fi

echo
echo "✓ All disables have JUSTIFICATION + ISSUE markers (security disables: resolvable ADRs)"
