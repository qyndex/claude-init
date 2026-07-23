#!/usr/bin/env bash
# M-23-26 — user-state mirror must honor CLAUDE_CONFIG_DIR. It hardcoded
# $HOME/.claude/projects, so on an install that sets CLAUDE_CONFIG_DIR (e.g.
# ~/.claude-qyndex) the mirror read the WRONG dir → empty tar → silent false
# success. Fix: derive the config root from CLAUDE_CONFIG_DIR (fallback
# $HOME/.claude); an empty/absent source must fail LOUD, not exit 0 pretending
# it mirrored something.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT/.claude/scripts/mirror-user-state.sh"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

# The script cd's to its own repo root and slugs $(pwd); to stay hermetic we run it
# from a temp repo copy so slug + dst land in the fixture, and point CLAUDE_CONFIG_DIR
# at a fixture config dir.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"; cfg="$tmp/cfg"
mkdir -p "$repo/.claude/scripts" "$cfg/projects" "$cfg/tasks"
cp "$SCRIPT" "$repo/.claude/scripts/"

# (1) CLAUDE_CONFIG_DIR honored: seed state under the FIXTURE config dir (not $HOME).
slug=$(cd "$repo" && pwd | sed 's|/|-|g')
mkdir -p "$cfg/projects/$slug"
echo '{"session":"x"}' > "$cfg/projects/$slug/session.json"

out=$(cd "$repo" && CLAUDE_CONFIG_DIR="$cfg" HOME="$tmp/nohome" bash .claude/scripts/mirror-user-state.sh 2>&1)
rc=$?
check "mirror exits 0 when CLAUDE_CONFIG_DIR has state" "$rc"
[ -f "$repo/.claude/.user-state-mirror/${slug}.tar.gz" ]
check "mirror reads from CLAUDE_CONFIG_DIR (archive created from fixture cfg)" $?
# The archive must actually contain the seeded file (not an empty tar).
tar -tzf "$repo/.claude/.user-state-mirror/${slug}.tar.gz" 2>/dev/null | grep -q 'session.json'
check "archive contains the seeded session state (not an empty tar)" $?

# (2) Empty/absent source under the configured dir must FAIL LOUD (non-zero), not
#     silently exit 0 (the false-success bug).
repo2="$tmp/repo2"; cfg2="$tmp/cfg2"
mkdir -p "$repo2/.claude/scripts" "$cfg2/projects"
cp "$SCRIPT" "$repo2/.claude/scripts/"
# No projects/<slug> dir seeded → nothing to mirror.
out2=$(cd "$repo2" && CLAUDE_CONFIG_DIR="$cfg2" HOME="$tmp/nohome" bash .claude/scripts/mirror-user-state.sh 2>&1)
rc2=$?
[ "$rc2" -ne 0 ]
check "absent user-state fails LOUD (non-zero exit, not silent success)" $?
printf '%s' "$out2" | grep -qiE 'no user-state|nothing to mirror|not found'
check "absent user-state prints a clear diagnostic" $?

# (3) Falls back to \$HOME/.claude when CLAUDE_CONFIG_DIR is unset (back-compat).
repo3="$tmp/repo3"; home3="$tmp/home3"
mkdir -p "$repo3/.claude/scripts" "$home3/.claude/projects"
cp "$SCRIPT" "$repo3/.claude/scripts/"
slug3=$(cd "$repo3" && pwd | sed 's|/|-|g')
mkdir -p "$home3/.claude/projects/$slug3"; echo x > "$home3/.claude/projects/$slug3/s.json"
( cd "$repo3" && unset CLAUDE_CONFIG_DIR; HOME="$home3" bash .claude/scripts/mirror-user-state.sh >/dev/null 2>&1 )
[ -f "$repo3/.claude/.user-state-mirror/${slug3}.tar.gz" ]
check "falls back to \$HOME/.claude when CLAUDE_CONFIG_DIR unset (back-compat)" $?

# (4) M-23-26 archaeology + bootstrap wiring (grep-level — these run the whole
#     adoption which needs a real repo; assert the wiring exists).
grep -q 'atlas-endpoints.sh' "$ROOT/.claude/scripts/adopt-archaeology.sh"
check "adopt-archaeology invokes the M-09a endpoint scraper (route inventory)" $?
grep -q 'initiative-state.sh sync' "$ROOT/.claude/scripts/adopt-state.sh"
check "adopt-state 'complete' bootstraps the living initiative STATE" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
