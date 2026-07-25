#!/usr/bin/env bash
# harvest-decisions.sh — spec-005 AC-3 (gap G3). The decision layer used to capture
# NOTHING automatically: every Constraint:/Rejected:/Directive: trailer the agent
# wrote lived only in git history, never in the ADR store. This harvests those
# trailers from a (merge) commit into a DRAFT ADR (status: proposed, OQ-2) so the
# decision log stays current as the project ships. A human flips proposed → accepted.
#
# Draft-only by design — it NEVER writes an accepted ADR. Deduped by a content hash
# of the trailer set (harvest_hash: in frontmatter): re-harvesting the same commit,
# or a different commit with the identical decision trailers, is a no-op.
#
# A commit with no Constraint/Rejected/Directive trailer harvests nothing (no noise).
# Requires at least one DIRECTIVE or CONSTRAINT — a decision needs a "why"/"what",
# not just Confidence/Scope-risk metadata.
#
# Usage:
#   harvest-decisions.sh <commit-ish>            # harvest that commit's trailers
#   harvest-decisions.sh <commit-ish> --dry-run  # report, write nothing
# Called from reconcile-shipped.sh per merged PR (mergeCommit).
# Test hooks: HARVEST_DECISIONS_DIR, HARVEST_BODY_FILE (read body from a file, not git).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

DEC_DIR="${HARVEST_DECISIONS_DIR:-.claude/memory/decisions}"
COMMIT="${1:-}"
DRY=0; [ "${2:-}" = "--dry-run" ] && DRY=1

[ -n "$COMMIT" ] || { echo "usage: harvest-decisions.sh <commit-ish> [--dry-run]"; exit 2; }

# Read the commit body: from a fixture file (tests) or from git.
if [ -n "${HARVEST_BODY_FILE:-}" ]; then
  body=$(cat "$HARVEST_BODY_FILE")
else
  command -v git >/dev/null 2>&1 || { echo "harvest-decisions: git required (or set HARVEST_BODY_FILE)"; exit 5; }
  body=$(git log -1 --format='%B' "$COMMIT" 2>/dev/null) || { echo "harvest-decisions: cannot read commit $COMMIT"; exit 5; }
fi

# Extract the decision trailers. Constraint/Rejected/Directive are the "decision"
# fields; Confidence/Scope-risk/Not-tested are metadata and do NOT count as a decision.
trailers=$(printf '%s\n' "$body" | grep -iE '^(Constraint|Rejected|Directive):' || true)
if [ -z "$trailers" ]; then
  [ "$DRY" -eq 1 ] && echo "harvest-decisions: $COMMIT has no decision trailers — nothing to harvest"
  exit 0
fi
# Require at least a Directive OR Constraint (a bare Rejected without context is noise).
if ! printf '%s\n' "$trailers" | grep -qiE '^(Constraint|Directive):'; then
  exit 0
fi

# Dedupe hash over the normalized trailer set.
hash=$(printf '%s' "$trailers" | tr -s ' ' | LC_ALL=C sort | shasum -a 256 2>/dev/null | cut -c1-16)
[ -n "$hash" ] || hash=$(printf '%s' "$trailers" | cksum | tr -d ' ')

# Already harvested? (same hash present in any ADR frontmatter.)
if grep -rqlF "harvest_hash: $hash" "$DEC_DIR" 2>/dev/null; then
  [ "$DRY" -eq 1 ] && echo "harvest-decisions: trailers already harvested (hash $hash) — skip"
  exit 0
fi

# Derive a slug from the first Directive (falls back to first Constraint).
seed=$(printf '%s\n' "$trailers" | grep -iE '^Directive:' | head -1 | sed -E 's/^[A-Za-z-]+:[[:space:]]*//')
[ -n "$seed" ] || seed=$(printf '%s\n' "$trailers" | grep -iE '^Constraint:' | head -1 | sed -E 's/^[A-Za-z-]+:[[:space:]]*//')
slug=$(printf '%s' "$seed" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//' | head -c 40)
[ -n "$slug" ] || slug="harvested-decision"

if [ "$DRY" -eq 1 ]; then
  echo "harvest-decisions: WOULD draft a proposed ADR (slug: $slug, hash: $hash) from:"
  printf '%s\n' "$trailers" | sed 's/^/    /'
  exit 0
fi

# Next ADR number in DEC_DIR (template is 0000).
last=$(ls "$DEC_DIR" 2>/dev/null | grep -oE '^[0-9]{4}' | sort -n | tail -1 || echo 0)
case "$last" in (*[!0-9]*|'') last=0 ;; esac
next=$(printf '%04d' $(( 10#$last + 1 )))
out="$DEC_DIR/${next}-${slug}.md"
[ -e "$out" ] && out="$DEC_DIR/${next}-${slug}-2.md"

today=$(date +%Y-%m-%d 2>/dev/null || echo "")
short=$(printf '%s' "$COMMIT" | cut -c1-12)

# Write a proposed ADR. Frontmatter matches the M-10 single-schema (status in
# frontmatter only) + adds harvest provenance. Body pre-fills Context/Decision from
# the trailers so a human can accept/refine rather than author from scratch.
{
  printf -- '---\n'
  printf 'name: %s-%s\n' "$next" "$slug"
  printf 'description: "ADR-%s (harvested draft): %s"\n' "$next" "$seed"
  printf 'status: proposed\n'
  printf 'created: %s\n' "$today"
  printf 'harvest_hash: %s\n' "$hash"
  printf 'harvested_from: %s\n' "$short"
  printf 'metadata:\n  type: decision\n  status: proposed\n  source: harvest-decisions.sh\n'
  printf -- '---\n\n'
  printf '# ADR-%s (harvested draft): %s\n\n' "$next" "$seed"
  printf '> Auto-drafted by harvest-decisions.sh from the decision trailers of commit `%s`.\n' "$short"
  printf '> **status: proposed** — a human must review and flip to `accepted` (or discard). Fill Context/Consequences.\n\n'
  printf '## Decision trailers (harvested)\n\n'
  printf '%s\n' "$trailers" | sed 's/^/- /'
  printf '\n## Context\n\n_Why did this come up? (fill from the commit / spec that triggered it.)_\n\n'
  printf '## Decision\n\n_State the decision crisply, drawn from the Directive/Constraint above._\n\n'
  printf '## Consequences\n\n- Positive: ...\n- Negative: ...\n\n'
  printf '## References\n\n- Commit: %s\n' "$short"
} > "$out"

# Best-effort reindex when writing into the real store.
if [ "$DEC_DIR" = ".claude/memory/decisions" ] && [ -x .claude/scripts/memory-index.sh ]; then
  bash .claude/scripts/memory-index.sh rebuild >/dev/null 2>&1 || true
fi

echo "harvest-decisions: drafted $out (proposed, hash $hash) — review + /adr-walk to accept"
