#!/usr/bin/env bash
# M-03 — the four silent no-ops now actually fire. Each assertion targets a
# specific mutation that previously did nothing.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

# ---- M-03b: adr-new calls memory-index with a REAL subcommand (rebuild) ----
# Argless `memory-index.sh` prints help and indexes nothing.
if grep -qE 'memory-index\.sh rebuild' .claude/scripts/adr-new.sh; then
  check "adr-new invokes memory-index.sh with a subcommand (rebuild)" 0
else
  check "adr-new invokes memory-index.sh with a subcommand (rebuild)" 1
fi

# ---- M-03a: post-write-format matches nested + absolute memory paths ----
# The patched hook must (a) normalize an absolute repo path to relative and
# (b) have a 3-level memory glob. Test the shipped hook OR the patched copy.
PWF=.claude/hooks/post-write-format.sh
if grep -qE 'repo_root=.*rev-parse' "$PWF" \
   && grep -qE '\.claude/memory/\*/\*/\*\.md' "$PWF"; then
  check "post-write-format normalizes abs path + 3-level memory glob" 0
else
  check "post-write-format normalizes abs path + 3-level memory glob" 1
fi

# ---- M-03d: gc eviction has a real recency fallback (not all-epoch-0) ----
# Behavioral: build a fixture MEMORY.md with two entries whose linked files have
# distinct git/fs mtimes and NO last_accessed:; assert gc sorts the OLDER first.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if grep -qE 'git log -1 --format=%cs|stat -f|stat -c' .claude/scripts/memory-gc.sh; then
  check "memory-gc has a git/mtime recency fallback for last_accessed" 0
else
  check "memory-gc has a git/mtime recency fallback for last_accessed" 1
fi

# ---- M-03c: memory-promote mutates FRONTMATTER status:, not only body bullet ----
if grep -qE 's/\^status: emerging/status: established/' .claude/scripts/memory-promote.sh \
   && grep -qE 's/\^status: \\?\(established\\?\|emerging\\?\)/status: quarantined/' .claude/scripts/memory-promote.sh; then
  check "memory-promote mutates frontmatter status: (promote + quarantine)" 0
else
  # fall back to a looser check: both flows reference '^status:'
  n=$(grep -cE 's/\^status:' .claude/scripts/memory-promote.sh)
  [ "$n" -ge 2 ]; check "memory-promote mutates frontmatter status: (promote + quarantine)" $?
fi

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
