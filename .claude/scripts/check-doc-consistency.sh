#!/usr/bin/env bash
# Checks that the root CLAUDE.md "Agent model assignments" table matches
# .claude/CLAUDE.md §V model routing. Exits 0 on match, 1 on drift.
# Wired into validate.sh [model-doc-consistency] category.
#
# Strategy: extract only "known agent" names from each model row, ignoring
# descriptor phrases like "keyword routing", "simple greps", "built-in".
# Known agents = lower-kebab-case tokens that appear in .claude/agents/**/*.md.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# Build set of known agent slugs from .claude/agents/**/*.md frontmatter
known_agents=()
while IFS= read -r f; do
  slug=$(grep -m1 '^name:' "$f" 2>/dev/null | sed 's/name:[[:space:]]*//' | tr -d '"' | xargs)
  [ -n "$slug" ] && known_agents+=("$slug")
done < <(find .claude/agents -name '*.md' -type f 2>/dev/null)

# Also accept the built-in "Explore" subagent (no .md file)
known_agents+=("Explore")

# Extract agent→model mappings: only tokens that match a known agent slug.
# Input: one model-routing line. Output: "agent:model" pairs.
parse_routing_line() {
  local line="$1" model="$2"
  # Get agents portion (after → or :)
  local agents
  agents=$(echo "$line" | sed 's/.*[→:]//')
  # Strip parenthetical notes and backtick phrases
  agents=$(echo "$agents" | sed 's/([^)]*)//g; s/`[^`]*`//g; s/\*\*//g')
  # Split on comma, trim whitespace
  echo "$agents" | tr ',' '\n' | sed 's/[[:space:]]//g' | grep -v '^$' | while read -r token; do
    for known in "${known_agents[@]}"; do
      if [ "$token" = "$known" ]; then
        printf '%s:%s\n' "$token" "$model"
        break
      fi
    done
  done
}

extract_mappings() {
  local file="$1"
  # Version-agnostic tier match: normalize to a tier keyword (opus/sonnet/haiku)
  # rather than a pinned version. A hardcoded version (e.g. "Opus 4.7") silently
  # drops a whole tier the moment the constitution bumps the version, making this
  # consistency gate pass by comparing empty-vs-empty. Match the tier, any minor.
  grep -E '^\-[[:space:]](\*\*)?(Opus|Sonnet|Haiku) 4\.[0-9]' "$file" \
    | while IFS= read -r line; do
        if echo "$line" | grep -qE 'Opus 4\.[0-9]';     then model="opus"
        elif echo "$line" | grep -qE 'Sonnet 4\.[0-9]'; then model="sonnet"
        elif echo "$line" | grep -qE 'Haiku 4\.[0-9]';  then model="haiku"
        else continue
        fi
        parse_routing_line "$line" "$model"
      done | sort
}

root_mappings=$(extract_mappings "CLAUDE.md")
claude_mappings=$(extract_mappings ".claude/CLAUDE.md")

# The constitution (.claude/CLAUDE.md) is the AUTHORITATIVE §V table — it must
# always parse. The root CLAUDE.md is the developer guide in greenfield (mirrors
# the table) but in BROWNFIELD it is the adopted project's own file, which has no
# §V model table — that's expected, not drift. So: require the table in the
# constitution; only cross-diff against root CLAUDE.md when root actually has one.
if [ -z "$claude_mappings" ]; then
  echo "ERROR: could not extract model mappings from .claude/CLAUDE.md (the constitution must carry the §V table)" >&2
  exit 1
fi

if [ -z "$root_mappings" ]; then
  echo "Model routing table present in .claude/CLAUDE.md §V; root CLAUDE.md has no §V table (brownfield project guide) — cross-file diff skipped."
  exit 0
fi

diff_out=$(diff <(echo "$root_mappings") <(echo "$claude_mappings") || true)

if [ -n "$diff_out" ]; then
  echo "Model routing drift between CLAUDE.md and .claude/CLAUDE.md §V:"
  echo "$diff_out"
  exit 1
fi

echo "Model routing tables consistent between CLAUDE.md and .claude/CLAUDE.md §V"

# e2e-audit docs-truth-1: also diff docs/ARCHITECTURE.md's agent table against
# live frontmatter — the table is the doc humans read; frontmatter is what runs.
arch_drift=0
if [ -f docs/ARCHITECTURE.md ]; then
  while IFS= read -r f; do
    an=$(grep -m1 '^name:' "$f" | sed 's/name:[[:space:]]*//' | tr -d '"' | xargs)
    am=$(grep -m1 '^model:' "$f" | sed 's/model:[[:space:]]*//' | xargs)
    [ -n "$an" ] && [ -n "$am" ] || continue
    row=$(grep -E "^\| \*\*$an\*\* \|" docs/ARCHITECTURE.md || true)
    if [ -z "$row" ]; then
      echo "ARCHITECTURE.md agent table missing agent: $an (model: $am)"
      arch_drift=$((arch_drift+1))
    elif ! echo "$row" | grep -q "| $am |"; then
      echo "ARCHITECTURE.md agent table model drift: $an should be '$am', row: $row"
      arch_drift=$((arch_drift+1))
    fi
  done < <(find .claude/agents -name '*.md' -type f 2>/dev/null)
  if [ "$arch_drift" -gt 0 ]; then
    echo "docs/ARCHITECTURE.md agent table drifted from .claude/agents frontmatter ($arch_drift issues)"
    exit 1
  fi
  echo "docs/ARCHITECTURE.md agent table matches .claude/agents frontmatter"
fi
exit 0
