#!/usr/bin/env bash
# lint-silent-failures.sh — audit silent-error patterns (Spec 001 AC-8).
#
# Greps the harness shell scripts for patterns that can hide real errors:
#   - the unconditional-true fallback
#   - the echo-zero fallback
#   - the stderr-to-null-device redirect
#   - errexit-less pipefail (set -uo pipefail with no -e flag)
# For each occurrence, it is "justified" iff a `# JUSTIFIED:` comment appears
# within 3 lines (the occurrence line or the 3 preceding lines). Emits a JSON
# report and exits non-zero when any occurrence is unjustified.
#
# Overridable for tests: SCAN_DIRS (space-separated roots, default the harness
# script + hook dirs) and AUDIT_FILE (default .claude/state/silent-failure-audit.json).

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

SCAN_DIRS="${SCAN_DIRS:-$ROOT/.claude/scripts $ROOT/.claude/hooks}"
AUDIT_FILE="${AUDIT_FILE:-$ROOT/.claude/state/silent-failure-audit.json}"
JUSTIFY_WINDOW=3

mkdir -p "$(dirname "$AUDIT_FILE")"

# Collect findings as newline-delimited JSON objects, then assemble.
findings_tmp="$(mktemp)"
trap 'rm -f "$findings_tmp"' EXIT

emit_finding() {
  # emit_finding <path> <line> <pattern> <justified true|false>
  jq -nc --arg p "$1" --argjson l "$2" --arg pat "$3" --argjson j "$4" \
    '{path:$p, line:$l, pattern:$pat, justified:$j}' >>"$findings_tmp"
}

# A finding is justified if any of the JUSTIFY_WINDOW lines up to and including
# the finding line contains "# JUSTIFIED:".
is_justified() {
  local file="$1" lineno="$2" start
  start=$(( lineno - JUSTIFY_WINDOW )); [ "$start" -lt 1 ] && start=1
  sed -n "${start},${lineno}p" "$file" | grep -q '# *JUSTIFIED:'
}

scan_pattern() {
  # scan_pattern <file> <grep-ere> <pattern-label>
  local file="$1" ere="$2" label="$3" lineno
  while IFS=: read -r lineno _; do
    [ -n "$lineno" ] || continue
    if is_justified "$file" "$lineno"; then
      emit_finding "$file" "$lineno" "$label" true
    else
      emit_finding "$file" "$lineno" "$label" false
    fi
  # JUSTIFIED: scanned file may be unreadable and grep returns 1 on no-match; muting stderr + the fallback keeps the loop iterating over zero hits rather than aborting the audit
  done < <(grep -nE "$ere" "$file" 2>/dev/null || true)
}

# Enumerate the .sh files to audit, skipping any that opt out via a top-of-file
# `lint-silent-failures: ignore-file` marker (used by this lint's own test, whose
# fixture content is intentional). Kept as a function to avoid nesting one
# process substitution inside another (which the bash parser mishandles).
enumerate_files() {
  local d cand
  for d in $SCAN_DIRS; do
    # JUSTIFIED: the guard skips a scan root that does not exist; find then contributes no files
    [ -d "$d" ] || continue
    while IFS= read -r cand; do
      # JUSTIFIED: the grep classifies the opt-out marker; muting its output and treating a non-match (exit 1) as "scan this file" is the intended flow
      if grep -q 'lint-silent-failures: ignore-file' "$cand" 2>/dev/null; then continue; fi
      printf '%s\n' "$cand"
    done < <(find "$d" -type f -name '*.sh')
  done
}

while IFS= read -r file; do
  [ -f "$file" ] || continue
  # JUSTIFIED: the next three label/regex arguments are literal pattern strings in the audit definition, not real silent failures
  scan_pattern "$file" '\|\| *true'            '|| true'
  scan_pattern "$file" '\|\| *echo +0'         '|| echo 0'
  scan_pattern "$file" '2>/dev/null'           '2>/dev/null'
  # set -uo pipefail WITHOUT an -e anywhere in the flags.
  while IFS=: read -r lineno content; do
    [ -n "$lineno" ] || continue
    case "$content" in
      *-*e*) : ;;  # has errexit somewhere in the set flags — fine
      *) if is_justified "$file" "$lineno"; then
           emit_finding "$file" "$lineno" 'set -uo pipefail (no -e)' true
         else
           emit_finding "$file" "$lineno" 'set -uo pipefail (no -e)' false
         fi ;;
    esac
  # JUSTIFIED: file may be unreadable and grep returns 1 when no matching line exists; muting stderr + the fallback keeps the loop iterating over zero hits rather than aborting the audit
  done < <(grep -nE '^[[:space:]]*set +-uo +pipefail' "$file" 2>/dev/null || true)
  # e2e-audit failure-recovery-2: a comment line directly after a backslash
  # continuation TERMINATES the command — trailing args/redirects silently
  # become a separate statement (the verified-merge.sh claude-spawn bug).
  # NEVER justifiable: the offending line IS a comment, so a JUSTIFIED tag
  # would self-justify the very pattern that caused the bug.
  while IFS= read -r lineno; do
    [ -n "$lineno" ] || continue
    emit_finding "$file" "$lineno" 'comment terminates backslash continuation' false
  # JUSTIFIED: awk over an unreadable file yields nothing — zero findings, the loop simply does not run
  done < <(awk 'prev !~ /^[[:space:]]*#/ && prev ~ /\\$/ && $0 ~ /^[[:space:]]*#/ {print NR} {prev=$0}' "$file" 2>/dev/null || true)
done < <(enumerate_files)

# Assemble the report.
total=$(wc -l <"$findings_tmp" | tr -d ' ')
[ -z "$total" ] && total=0
if [ "$total" -eq 0 ]; then
  printf '%s\n' '{"total":0,"justified":0,"unjustified":0,"findings":[]}' >"$AUDIT_FILE"
else
  jq -s '{
    total: length,
    justified: ([.[] | select(.justified)] | length),
    unjustified: ([.[] | select(.justified | not)] | length),
    findings: .
  }' "$findings_tmp" >"$AUDIT_FILE"
fi

unjustified=$(jq -r '.unjustified' "$AUDIT_FILE")
echo "silent-failure audit: $unjustified unjustified of $(jq -r '.total' "$AUDIT_FILE") (report: $AUDIT_FILE)"

# ─── Baseline ratchet (spec 004 T-133) ──────────────────────────────────
# 223 pre-existing unjustified swallows live in the harness's own scripts —
# mostly defensive 2>/dev/null and || true. Justifying each inline risks
# rubber-stamping the very anti-pattern this gate guards against, so instead we
# LOCK the known set as a baseline keyed on path:line:pattern and fail only on
# NEW unjustified swallows. The baseline is a ceiling: it can only shrink.
# Regenerate intentionally with UPDATE_SILENT_BASELINE=1 after burning entries
# down. Burn-down tracked as a debt task.
BASELINE_FILE="${SILENT_BASELINE_FILE:-$ROOT/.claude/state/silent-failure-baseline.json}"

# Current unjustified keys, repo-relative + stable across checkouts.
current_keys="$(jq -r --arg root "$ROOT/" \
  '.findings[]? | select(.justified|not) | ((.path|sub($root;"")) + ":" + (.line|tostring) + ":" + .pattern)' \
  "$AUDIT_FILE" | sort)"

if [ "${UPDATE_SILENT_BASELINE:-0}" = "1" ]; then
  printf '%s\n' "$current_keys" | grep . | jq -R . | jq -s . >"$BASELINE_FILE"
  echo "silent-failure baseline written: $(printf '%s\n' "$current_keys" | grep -c .) entries -> $BASELINE_FILE"
  exit 0
fi

[ "$unjustified" -eq 0 ] && exit 0

# No baseline yet -> strict mode (any unjustified fails), preserving old behavior.
if [ ! -f "$BASELINE_FILE" ]; then
  echo "::error::no silent-failure baseline; run UPDATE_SILENT_BASELINE=1 to lock the current set, then burn it down"
  exit 1
fi

baseline_keys="$(jq -r '.[]' "$BASELINE_FILE" | sort)"
# Keys present now but absent from the baseline = newly-introduced swallows.
new_list="$(comm -23 <(printf '%s\n' "$current_keys") <(printf '%s\n' "$baseline_keys") | grep . || true)"
if [ -n "$new_list" ]; then
  echo "::error::new unjustified silent-failure(s) beyond the baseline — add '# JUSTIFIED:' within 3 lines or fix:"
  printf '%s\n' "$new_list"
  exit 1
fi
baseline_count="$(printf '%s\n' "$baseline_keys" | grep -c . || true)"
echo "silent-failure: $unjustified within baseline of $baseline_count (no new swallows)"
exit 0
