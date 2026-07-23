#!/usr/bin/env bash
# M-11 — executable ADR supersession (mechanical consumers only). A supersede
# command must flip the OLD ADR's frontmatter (status: superseded, superseded_by:
# ADR-<new>), stamp the NEW ADR (supersedes: ADR-<old>), and rebuild the index so
# recall's existing -5 penalty (memory-recall.sh:67, already live) excludes it.
#
# The §V-auto-amend / prompt-consumer-filtering parts are constitution-blocked and
# UNTESTABLE-BY-RIG (plan-acknowledged) — NOT covered here. This tests only the
# deterministic mechanical convergence: frontmatter flip + edges + index.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 0; }

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

# Hermetic temp repo with the real scripts + two fixture ADRs.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/scripts/lib" "$tmp/.claude/memory/decisions" "$tmp/.claude/state/locks"
cp .claude/scripts/memory-index.sh "$tmp/.claude/scripts/"
cp .claude/scripts/lib/with-lock.sh "$tmp/.claude/scripts/lib/"

cat > "$tmp/.claude/memory/decisions/0001-old.md" <<'EOF'
---
name: 0001-old
description: "ADR-0001: the superseded decision"
status: accepted
created: 2026-01-01
metadata:
  type: decision
  status: accepted
---
# ADR-0001: old
Body.
EOF

cat > "$tmp/.claude/memory/decisions/0002-new.md" <<'EOF'
---
name: 0002-new
description: "ADR-0002: the replacement"
status: accepted
created: 2026-02-01
metadata:
  type: decision
  status: accepted
---
# ADR-0002: new
Body.
EOF

( cd "$tmp" && bash .claude/scripts/memory-index.sh rebuild >/dev/null 2>&1 )

# Run the supersession: 0002 supersedes 0001.
( cd "$tmp" && bash .claude/scripts/memory-index.sh supersede 0001-old 0002-new >/dev/null 2>&1 )
rc=$?
check "supersede subcommand exits 0" "$rc"

OLD="$tmp/.claude/memory/decisions/0001-old.md"
NEW="$tmp/.claude/memory/decisions/0002-new.md"

# (1) OLD ADR frontmatter flipped: status superseded + superseded_by set.
awk '/^---$/{n++} n==1 && /^status: superseded$/{f=1} END{exit !f}' "$OLD"
check "old ADR frontmatter status flipped to 'superseded'" $?
awk '/^---$/{n++} n==1 && /^superseded_by: ADR-0002/{f=1} END{exit !f}' "$OLD"
check "old ADR frontmatter carries superseded_by: ADR-0002" $?

# (2) NEW ADR stamped with the reciprocal edge.
awk '/^---$/{n++} n==1 && /^supersedes: ADR-0001/{f=1} END{exit !f}' "$NEW"
check "new ADR frontmatter carries supersedes: ADR-0001" $?

# (3) The body of the OLD ADR must be untouched (frontmatter-only mutation — no
#     sed-on-body bug). Its "# ADR-0001: old" heading + "Body." must survive.
grep -q '^# ADR-0001: old' "$OLD" && grep -q '^Body\.$' "$OLD"
check "old ADR body preserved (frontmatter-only mutation)" $?

# (4) Index reflects the supersession: the old entry's superseded_by is populated.
old_sb=$(cd "$tmp" && jq -r 'select(.id=="0001-old") | .superseded_by' .claude/memory/index.jsonl 2>/dev/null)
[ "$old_sb" = "ADR-0002" ] || [ "$old_sb" = "0002-new" ]
check "index entry for old ADR has non-empty superseded_by (recall -5 penalty activates)" $?

# (5) NEGATIVE/idempotence: re-running supersede on an already-superseded pair must
#     not duplicate the frontmatter keys (no double superseded_by lines).
( cd "$tmp" && bash .claude/scripts/memory-index.sh supersede 0001-old 0002-new >/dev/null 2>&1 )
dupes=$(grep -cE '^superseded_by:' "$OLD")
[ "$dupes" -eq 1 ]
check "idempotent: superseded_by not duplicated on re-run (got $dupes)" $?

# (6) Guard: superseding a non-existent ADR must fail loudly (not silently no-op).
( cd "$tmp" && bash .claude/scripts/memory-index.sh supersede 9999-nope 0002-new >/dev/null 2>&1 )
[ "$?" -ne 0 ]
check "supersede fails loudly on a missing old-ADR id" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
