#!/usr/bin/env bash
# check-model-consistency.sh — every agent's model matches §V (Spec 001 AC-11).
#
# Parses the §V <model_routing> table in .claude/CLAUDE.md into a name→tier map
# (opus|sonnet|haiku), then walks agent definitions and verifies each `model:`
# frontmatter resolves to the tier §V assigns that agent. A file carrying a
# `model-consistency: ignore` marker is skipped. Exits non-zero on any mismatch.
#
# Model id normalization: opus / "Opus 4.7" / claude-opus-4-7 all → opus (etc).
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
#   - **Opus 4.7** → architect, implementer, … (notes)
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
echo "model-consistency: all agents match §V"
exit 0
