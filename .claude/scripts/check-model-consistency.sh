#!/usr/bin/env bash
# check-model-consistency.sh — every agent's model matches §V (Spec 001 AC-11).
#
# Parses the §V <model_routing> table in .claude/CLAUDE.md into a name→tier map
# (opus|sonnet|haiku), then walks agent definitions and verifies each `model:`
# frontmatter resolves to the tier §V assigns that agent. A file carrying a
# `model-consistency: ignore` marker is skipped. Exits non-zero on any mismatch.
#
# Model id normalization: opus / "Opus 4.8" / claude-opus-4-7 all → opus (etc).
#
# Overridable for tests: CONSTITUTION, AGENTS_DIR.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

CONSTITUTION="${CONSTITUTION:-$ROOT/.claude/CLAUDE.md}"
AGENTS_DIR="${AGENTS_DIR:-$ROOT/.claude/agents}"

# JUSTIFIED: a missing constitution is a hard error for this check — report and fail, do not silently pass
if [ ! -f "$CONSTITUTION" ]; then
  echo "✗ constitution not found: $CONSTITUTION"
  exit 1
fi

# Normalize any model string to a tier keyword.
normalize_tier() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    *opus*)   echo opus ;;
    *sonnet*) echo sonnet ;;
    *haiku*)  echo haiku ;;
    *)        echo unknown ;;
  esac
}

# Parse §V into "name<TAB>tier" lines. Each bullet is:
#   - **Opus 4.8** → architect, implementer, … (notes)
# We take the bolded tier and split the arrow's RHS on commas, stripping
# parenthetical notes and backticked/`Explore` style names.
parse_routing() {
  awk '
    /^## V\./ { inv=1; next }
    /^## VI\./ { inv=0 }
    inv && /\*\*.*\*\* *(→|->)/ {
      line=$0
      # tier = text between the first pair of **
      t=line; sub(/^[^*]*\*\*/,"",t); sub(/\*\*.*$/,"",t)
      # rhs = everything after the arrow
      r=line; sub(/^.*(→|->)/,"",r)
      sub(/\(.*$/,"",r)               # drop trailing "(notes)"
      n=split(r, parts, ",")
      for (i=1;i<=n;i++) {
        name=parts[i]
        gsub(/[`*]/,"",name)
        gsub(/^[ \t]+|[ \t]+$/,"",name)
        # take the first token (drop trailing words like "subagent")
        split(name, w, " "); name=w[1]
        if (name != "") print name "\t" t
      }
    }
  ' "$CONSTITUTION"
}

# Build the expected map.
declare_map() { :; }
routing="$(parse_routing)"

expected_tier() { # expected_tier <agent-name> → tier or empty
  # JUSTIFIED: read || true — when awk emits no line (agent not in §V) read exits 1; that empty $t is the intended "unknown tier" signal, normalized below
  printf '%s\n' "$routing" | awk -F'\t' -v n="$1" '$1==n {print $2; exit}' | { read -r t || true; normalize_tier "$t"; }
}

issues=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  # JUSTIFIED: the marker grep classifies opt-out files; a non-match (exit 1) is the normal "check this file" path
  if grep -q 'model-consistency: ignore' "$f" 2>/dev/null; then continue; fi

  name="$(awk -F': *' '/^name:/{print $2; exit}' "$f" | tr -d '[:space:]')"
  [ -n "$name" ] || name="$(basename "$f" .md)"
  declared="$(awk -F': *' '/^model:/{print $2; exit}' "$f")"
  [ -n "$declared" ] || continue   # no model: line → nothing to check

  want="$(expected_tier "$name")"
  [ -z "$want" ] || [ "$want" = "unknown" ] && continue   # agent not in §V → not our concern

  got="$(normalize_tier "$declared")"
  if [ "$got" != "$want" ]; then
    echo "✗ $f: model '$declared' (→$got) but §V assigns '$name' to $want"
    issues=$((issues + 1))
  fi
# JUSTIFIED: find 2>/dev/null — hides "no such directory" if .claude/agents is absent; an empty result means zero agents to check, not an error
done < <(find "$AGENTS_DIR" -type f -name '*.md' 2>/dev/null)

if [ "$issues" -gt 0 ]; then
  echo "model-consistency: $issues mismatch(es) vs §V"
  exit 1
fi

# ─── Stale-version scan (Spec 003 AC-12) ──────────────────────────────────────
# Agent frontmatter normalizes opus-4-7 → opus, so a tier check can't catch a
# workflow/doc that pins the *superseded* version. Scan .github/workflows/** and
# docs/** for the now-stale literal so a model bump can't strand a LIVE pin. The
# stale version is whatever §V no longer lists; today that is opus 4.7.
#
# Exclude archival/historical doc trees: test-run logs and factory-history record
# what *did* run on a past date (e.g. "| Runner | Claude Opus 4.7 |") — they are
# immutable transcripts, not live config. Rewriting them would falsify history, and
# AC-12's intent is "no live pin stranded", not "no doc may mention a prior model".
# A path segment named test-runs/, factory-history/, or archive/ marks such a tree.
STALE_PATTERN='claude-opus-4-7|opus-4-7|Opus 4\.7'
stale_hits=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  grep -q 'model-consistency: ignore' "$f" 2>/dev/null && continue
  if grep -nE "$STALE_PATTERN" "$f" >/dev/null 2>&1; then
    grep -nE "$STALE_PATTERN" "$f" | sed "s|^|✗ stale model ref $f:|"
    stale_hits=$((stale_hits + 1))
  fi
# JUSTIFIED: find 2>/dev/null hides absent dirs; empty result = nothing to scan, not an error
done < <(find "$ROOT/.github/workflows" "$ROOT/docs" \
  \( -path '*/test-runs/*' -o -path '*/factory-history/*' -o -path '*/archive/*' \) -prune -o \
  -type f \( -name '*.yml' -o -name '*.yaml' -o -name '*.md' \) -print 2>/dev/null)

# STALE_SCAN_ONLY=1 → run only the stale scan (used by AC-12 test fixtures).
if [ "${STALE_SCAN_ONLY:-0}" = "1" ]; then
  if [ "$stale_hits" -gt 0 ]; then echo "model-consistency: $stale_hits stale-version ref(s)"; exit 1; fi
  echo "model-consistency: no stale-version refs"; exit 0
fi

if [ "$stale_hits" -gt 0 ]; then
  echo "model-consistency: $stale_hits stale-version ref(s) in workflows/docs"
  exit 1
fi

# ─── Cross-model review gate (gap-audit G46) ─────────────────────────────────
# Same-model review shares blind spots: the CI gating reviewer
# (claude-review.yml `review` job) must NOT resolve to the same tier as the
# implementer agent. Overridable for tests: REVIEW_WORKFLOW.
REVIEW_WORKFLOW="${REVIEW_WORKFLOW:-$ROOT/.github/workflows/claude-review.yml}"
if [ -f "$REVIEW_WORKFLOW" ]; then
  impl_tier="$(expected_tier implementer)"
  ci_model="$(grep -E '^[[:space:]]*model: claude-' "$REVIEW_WORKFLOW" | head -1 | awk -F': *' '{print $2}')"
  if [ -n "$ci_model" ] && [ "$impl_tier" != "unknown" ] && [ -n "$impl_tier" ]; then
    ci_tier="$(normalize_tier "$ci_model")"
    if [ "$ci_tier" = "$impl_tier" ]; then
      echo "✗ cross-model gate: CI reviewer ($ci_model → $ci_tier) is the SAME tier as the implementer agent ($impl_tier) — route the gating review to a different model (gap-audit G46)"
      echo "model-consistency: cross-model review gate violated"
      exit 1
    fi
  fi
fi

echo "model-consistency: all agents match §V; no stale-version refs; review is cross-model"
exit 0
