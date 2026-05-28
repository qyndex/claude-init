#!/usr/bin/env bash
# Test for check-model-consistency.sh (Spec 001 AC, Phase 4).
#
# Tagged: AC-11
#
# Verifies the checker flags an agent whose `model:` frontmatter contradicts the
# §V routing table in .claude/CLAUDE.md, and that a `<!-- model-consistency:
# ignore -->` marker suppresses the finding. Runs against a hermetic fixture tree
# (CONSTITUTION + AGENTS_DIR overrides) so the real harness is untouched.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CHECK="$ROOT/.claude/scripts/check-model-consistency.sh"

pass=0
fail=0
fails=()

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CONSTITUTION="$TMP/CLAUDE.md"
export AGENTS_DIR="$TMP/agents"
mkdir -p "$AGENTS_DIR"

# Minimal §V table: implementer→Opus, planner→Sonnet.
cat >"$CONSTITUTION" <<'EOF'
## V. `<model_routing>`

- **Opus 4.7** → implementer (hard thinking)
- **Sonnet 4.6** → planner (daily driver)
- **Haiku 4.5** → Explore

This list is authoritative — every agent's frontmatter `model:` must match it.
EOF

mk_agent() { # mk_agent <name> <model> [marker]
  local f="$AGENTS_DIR/$1.md"
  {
    echo "---"
    echo "name: $1"
    echo "model: $2"
    echo "---"
    [ -n "${3:-}" ] && echo "$3"
    echo "# $1"
  } >"$f"
}

expect_rc() { local label="$1" actual="$2" want="$3"; if [ "$actual" = "$want" ]; then pass=$((pass+1)); else fail=$((fail+1)); fails+=("$label: rc=$actual want=$want"); fi; }

# 1. All consistent → exit 0.
mk_agent implementer opus
mk_agent planner sonnet
bash "$CHECK" >/dev/null 2>&1; expect_rc "consistent tree passes" "$?" "0"

# 2. Mismatch (implementer marked sonnet, but §V says Opus) → exit non-zero.
mk_agent implementer sonnet
bash "$CHECK" >/dev/null 2>&1; rc=$?; [ "$rc" -ne 0 ]; expect_rc "mismatch is flagged (non-zero)" "$?" "0"

# 3. The ignore marker suppresses the finding → back to exit 0.
mk_agent implementer sonnet '<!-- model-consistency: ignore -->'
bash "$CHECK" >/dev/null 2>&1; expect_rc "ignore marker bypasses the check" "$?" "0"

echo "---"
echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -gt 0 ]; then
  printf '  - %s\n' "${fails[@]}"
  exit 1
fi
exit 0
