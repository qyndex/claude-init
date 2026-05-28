#!/usr/bin/env bash
# spec-drift scan (non-interactive) — Round 13 Fix 3.
#
# Closes "Loop 6" (named in findings-to-tasks.sh's header): /spec-drift-check PRINTED
# drift but never opened follow-ups, so silent regressions in long-lived shipped code
# went un-actioned. This is the scheduled scanner: it re-runs each shipped spec's
# `accept:` command, records regressions to a dated incidents file, and queues
# `priority: spec-drift` tasks via findings-to-tasks.sh.
#
# Invoked WEEKLY by dream-cron (the interactive /spec-drift-check command is for ad-hoc use).

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"

date_label="$(date +%Y-%m-%d)"
drift_report=".claude/memory/incidents/drift-${date_label}.md"
findings="$(mktemp)"
mkdir -p .claude/memory/incidents

printf '# Spec drift scan — %s\n\n' "$date_label" > "$drift_report"

shopt -s nullglob
drift_count=0 checked=0
for spec in specs/active/*.md specs/archive/*/*.md specs/archive/*.md; do
  [ -f "$spec" ] || continue
  grep -qE '^status:[[:space:]]*shipped' "$spec" || continue
  id="$(basename "$spec" .md)"
  num="${id%%-*}"   # numeric spec id used in TASKS.md as spec:<num>
  # Find the spec's accept: command from TASKS.md (first task for this spec).
  accept_cmd="$(grep -A6 "spec:${num}\b" tasks/TASKS.md 2>/dev/null | grep -m1 'accept:' | sed 's/.*accept:[[:space:]]*//')"
  [ -z "$accept_cmd" ] && continue
  checked=$((checked + 1))
  # Re-run it; a non-zero exit = drift. (Same eval the interactive command uses; the
  # pre-bash-guard hook still vets the command string.)
  if ! eval "$accept_cmd" >/dev/null 2>&1; then
    {
      echo "## ${id} — DRIFT"
      echo "- \`accept:\` command no longer exits 0: \`$accept_cmd\`"
      echo
    } >> "$drift_report"
    echo "- [ ] Spec drift: ${id} — \`$accept_cmd\` regressed; re-verify or update the spec (owner: @spec-owner)" >> "$findings"
    drift_count=$((drift_count + 1))
  fi
done

if [ "$drift_count" -gt 0 ]; then
  bash .claude/scripts/findings-to-tasks.sh "$findings" --priority spec-drift --source "spec-drift-scan:${date_label}"
  echo "spec-drift-scan: checked $checked shipped spec(s); $drift_count drift(s) → tasks; report $drift_report"
else
  rm -f "$drift_report"   # no empty reports
  echo "spec-drift-scan: checked $checked shipped spec(s); no drift detected"
fi
rm -f "$findings"
