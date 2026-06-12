#!/usr/bin/env bash
# Documentation-truthfulness audit (Spec 001 AC-23).
#
# Scans docs for enforcement claims — "enforced by X", "blocked by X",
# "required by X", "gated by X" — and verifies that each named gate X actually
# exists in the harness as one of:
#   - an executable .claude/scripts/*.sh (or scripts/**/*.sh),
#   - a .github/workflows/*.yml workflow,
#   - a .claude/hooks/*.sh hook.
# An orphan claim (the doc promises a gate that does not exist) is a lie the
# harness tells about itself — exactly the drift this audit catches. Any orphan
# → non-zero exit, with the offending file:line and gate printed.
#
# Scan set:
#   - default: docs/**/*.md, CLAUDE.md, .claude/CLAUDE.md, .claude/skills/**/SKILL.md
#   - AUDIT_DOC_ROOT=<dir>: scan markdown under <dir> instead (used by the test).
# Gate resolution ALWAYS runs against the real repo, so a sandboxed doc may
# legitimately reference a real gate like validate.sh.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# ─── Collect the docs to scan ───────────────────────────────────────────
docs=()
if [ -n "${AUDIT_DOC_ROOT:-}" ]; then
  # JUSTIFIED: find 2>/dev/null — an absent/empty AUDIT_DOC_ROOT yields no docs; that is "nothing to audit", not an error
  while IFS= read -r f; do docs+=("$f"); done < <(find "$AUDIT_DOC_ROOT" -type f -name '*.md' 2>/dev/null)
else
  cd "$ROOT"
  # JUSTIFIED: find 2>/dev/null on docs/ + .claude/skills/ — a repo without those dirs simply contributes no docs to the scan, not an error
  while IFS= read -r f; do docs+=("$f"); done < <(
    # docs/research/ excluded: audit/research artifacts quote stale claims as findings
    find docs -type f -name '*.md' -not -path 'docs/research/*' 2>/dev/null
    [ -f CLAUDE.md ] && printf '%s\n' CLAUDE.md
    [ -f .claude/CLAUDE.md ] && printf '%s\n' .claude/CLAUDE.md
    # JUSTIFIED: find 2>/dev/null — absent .claude/skills contributes no SKILL.md docs, not an error
    find .claude/skills -type f -name 'SKILL.md' 2>/dev/null
  )
fi

# ─── Gate resolver — does this named gate exist in the real harness? ─────
gate_exists() {
  local gate="$1"
  case "$gate" in
    *.sh)
      # JUSTIFIED: find 2>/dev/null — suppresses "no such dir"; grep -q . is the real resolve signal (a match means the gate exists)
      find "$ROOT/.claude/scripts" "$ROOT/.claude/hooks" -type f -name "$gate" 2>/dev/null | grep -q .
      ;;
    *.yml|*.yaml)
      # JUSTIFIED: find 2>/dev/null — suppresses "no such dir"; grep -q . is the real resolve signal (a match means the workflow exists)
      find "$ROOT/.github/workflows" -type f -name "$gate" 2>/dev/null | grep -q .
      ;;
  esac
}

orphans=0
checked=0

for doc in "${docs[@]}"; do
  [ -f "$doc" ] || continue
  # Pull out every "<phrase> by <gate>" occurrence. The gate token is the first
  # whitespace-delimited word after "by ", with surrounding markdown/punctuation
  # stripped. grep -n keeps the line number for the report.
  while IFS=: read -r lineno text; do
    [ -n "$lineno" ] || continue
    # Extract each gate token on the line (there can be more than one claim).
    # Strip the leading "<phrase> by ", then trim only LEADING and TRAILING
    # markdown/punctuation — never internal dots, so "validate.sh" stays intact
    # while a sentence-final "pre-bash-guard.sh." loses just its trailing period.
    gates=$(printf '%s\n' "$text" \
      | grep -oiE '(enforced|blocked|required|gated) by [^ ]+' \
      | sed -E 's/^[a-zA-Z]+ by //' \
      | sed -E 's/^[`*"(]+//; s/[`*",.;:)]+$//' )
    while IFS= read -r gate; do
      [ -n "$gate" ] || continue
      # Only audit tokens that name a concrete gate FILE — i.e. carry a .sh /
      # .yml / .yaml extension. Bare hyphenated nouns ("verification-before-
      # completion") and slash-commands ("/pii-audit") are prose references, not
      # gate-file claims, and would otherwise produce false orphans.
      case "$gate" in
        *.sh|*.yml|*.yaml) : ;;
        *) continue ;;
      esac
      checked=$((checked + 1))
      if ! gate_exists "$gate"; then
        printf 'ORPHAN: %s:%s claims a gate that does not exist: %s\n' "$doc" "$lineno" "$gate"
        orphans=$((orphans + 1))
      fi
    done <<EOF
$gates
EOF
  # JUSTIFIED: grep 2>/dev/null — a doc with zero claim lines (grep exit 1) is the common case; the empty loop body is the intended no-op, not an error
  done < <(grep -niE '(enforced|blocked|required|gated) by ' "$doc" 2>/dev/null)

  # ── Active-voice claims (e2e-audit docs-truth-1) — "validate.sh enforces",
  # "no-issue-authority.yml fails the build". Same resolver, opposite word order:
  # gate-file token immediately followed by an enforcement verb.
  while IFS=: read -r lineno text; do
    [ -n "$lineno" ] || continue
    gates=$(printf '%s\n' "$text" \
      | grep -oiE '`?[A-Za-z0-9._-]+\.(sh|ya?ml)`? +(enforces|blocks|fails|gates|rejects|halts)' \
      | sed -E 's/ +(enforces|blocks|fails|gates|rejects|halts)$//i; s/^`//; s/`$//')
    while IFS= read -r gate; do
      [ -n "$gate" ] || continue
      checked=$((checked + 1))
      if ! gate_exists "$gate"; then
        printf 'ORPHAN: %s:%s active-voice claim names a gate that does not exist: %s\n' "$doc" "$lineno" "$gate"
        orphans=$((orphans + 1))
      fi
    done <<EOF
$gates
EOF
  # JUSTIFIED: grep 2>/dev/null — zero active-voice claim lines is the common case; the empty loop is the intended no-op
  done < <(grep -niE '[A-Za-z0-9._-]+\.(sh|ya?ml)`? +(enforces|blocks|fails|gates|rejects|halts)' "$doc" 2>/dev/null)

  # ── Required-check claims (e2e-audit docs-truth-1) — a doc asserting
  # "`x` is a required check" must name a context that exists in
  # .github/rulesets/main-protection.json, or the promised merge gate is fiction.
  if [ -f "$ROOT/.github/rulesets/main-protection.json" ] && command -v jq >/dev/null 2>&1; then
    contexts=" $(jq -r '.. | .required_status_checks? // empty | .[]? | .context? // empty' "$ROOT/.github/rulesets/main-protection.json" 2>/dev/null | tr '\n' ' ') "
    while IFS=: read -r lineno text; do
      [ -n "$lineno" ] || continue
      # Backticked extensionless tokens on a "required ... check" line are check-name claims.
      names=$(printf '%s\n' "$text" | grep -oE '`[a-z0-9][a-z0-9-]*`' | tr -d '`' || true)
      while IFS= read -r name; do
        [ -n "$name" ] || continue
        checked=$((checked + 1))
        case "$contexts" in
          *" $name "*) : ;;
          *)
            printf 'ORPHAN: %s:%s claims required check not in main-protection.json contexts: %s\n' "$doc" "$lineno" "$name"
            orphans=$((orphans + 1))
            ;;
        esac
      done <<EOF
$names
EOF
    # JUSTIFIED: grep 2>/dev/null — zero required-check claim lines is the common case; the empty loop is the intended no-op
    done < <(grep -niE 'required (status )?check' "$doc" 2>/dev/null | grep ':[^:]*`' || true)
  fi
done

if [ "$orphans" -gt 0 ]; then
  printf 'audit-doc-claims: %d orphan claim(s) of %d checked\n' "$orphans" "$checked" >&2
  exit 1
fi
printf 'audit-doc-claims: all %d gate claims resolve to real gates\n' "$checked"
exit 0
