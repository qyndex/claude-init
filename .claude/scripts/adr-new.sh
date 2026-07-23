#!/usr/bin/env bash
# ADR scaffolder — gap-audit G39/G43.
# Zero ADRs ever got created because creation was purely instruction-driven.
# This is the mechanical path: auto-numbers, copies the template, stamps
# provenance (written_by + source_session — the "populated by hook" claim in
# the template now has a real populater), and rebuilds the memory index.
#
# Usage:
#   bash .claude/scripts/adr-new.sh "<title>" [--by architect|human|dream|reviewer|debugger|security] [--tags <tags>]
#   bash .claude/scripts/adr-new.sh "use postgres for billing" --by architect
#
# Prints the created path. Body content is then filled by the caller
# (human, or the parent session persisting an architect handoff).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

DIR=".claude/memory/decisions"
TEMPLATE="$DIR/0000-template.md"
[ -f "$TEMPLATE" ] || { echo "adr-new: template missing at $TEMPLATE" >&2; exit 1; }

title="${1:-}"
[ -z "$title" ] && { echo "Usage: adr-new.sh \"<title>\" [--by <who>] [--tags <tags>]" >&2; exit 1; }
shift

by="human"
tags="architecture"
subsystem="general"
while [ $# -gt 0 ]; do
  case "$1" in
    --by) by="$2"; shift 2 ;;
    --tags) tags="$2"; shift 2 ;;
    --subsystem) subsystem="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Next number: scan existing NNNN-*.md (template is 0000)
# JUSTIFIED: ls suppressed — an empty decisions dir yields no list and the seed 0 gives ADR-0001
last=$(ls "$DIR" 2>/dev/null | grep -oE '^[0-9]{4}' | sort -n | tail -1 || echo 0)
case "$last" in (*[!0-9]*|'') last=0 ;; esac
next=$(printf '%04d' $(( 10#$last + 1 )))

slug=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//' | head -c 48)
out="$DIR/${next}-${slug}.md"
[ -e "$out" ] && { echo "adr-new: $out already exists" >&2; exit 1; }

today=$(date +%Y-%m-%d)
# Provenance: session id from the live session record when an agent writes
session_id=""
if [ "$by" != "human" ]; then
  # JUSTIFIED: a missing/corrupt session record degrades to empty provenance — still distinguishable from human (written_by)
  session_id=$(jq -r '.session_id // ""' .claude/memory/.cache/current-session.json 2>/dev/null || echo "")
fi

sed -e "s/^name: 0000-decision-template/name: ${next}-${slug}/" \
    -e "s/description: ADR template — copy to a new file and fill in./description: ADR-${next}: ${title}/" \
    -e "s/  status: template/  status: proposed/" \
    -e "s/^created: YYYY-MM-DD/created: ${today}/" \
    -e "s/# ADR-0000: <Decision Title>/# ADR-${next}: ${title}/" \
    -e "s/- \*\*Status\*\*: proposed | accepted | superseded by ADR-XXXX | deprecated/- **Status**: proposed/" \
    -e "s/- \*\*Date\*\*: YYYY-MM-DD/- **Date**: ${today}/" \
    -e "s/- \*\*written_by\*\*: human | architect | dream | reviewer | debugger | security   # Round 5 C2 — provenance/- **written_by**: ${by}/" \
    -e "s|- \*\*source_session\*\*: <session-id>.*|- **source_session**: ${session_id}|" \
    -e "s|- \*\*last_verified\*\*: YYYY-MM-DD.*|- **last_verified**: ${today}|" \
    -e "s|- \*\*Tags\*\*: architecture .*|- **Tags**: ${tags}|" \
    -e "s|- \*\*subsystem\*\*: <one-word.*|- **subsystem**: ${subsystem}|" \
    "$TEMPLATE" > "$out"

# Keep the recall index current
# M-03: memory-index.sh with NO subcommand prints help and indexes nothing — the
# new ADR never entered the index. Pass `rebuild` (a real subcommand) so the ADR
# is actually indexed.
# JUSTIFIED: index rebuild is best-effort — a failure leaves the new ADR discoverable by path; doctor flags stale indexes
bash .claude/scripts/memory-index.sh rebuild >/dev/null 2>&1 || true

echo "$out"
