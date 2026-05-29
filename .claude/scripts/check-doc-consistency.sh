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

if [ -z "$root_mappings" ]; then
  echo "ERROR: could not extract model mappings from CLAUDE.md" >&2
  exit 1
fi
if [ -z "$claude_mappings" ]; then
  echo "ERROR: could not extract model mappings from .claude/CLAUDE.md" >&2
  exit 1
fi

diff_out=$(diff <(echo "$root_mappings") <(echo "$claude_mappings") || true)

if [ -n "$diff_out" ]; then
  echo "Model routing drift between CLAUDE.md and .claude/CLAUDE.md §V:"
  echo "$diff_out"
  exit 1
fi

echo "Model routing tables consistent between CLAUDE.md and .claude/CLAUDE.md §V"
exit 0
