#!/usr/bin/env bash
# AC-15/16/17: spec-status-sync.sh advances approved→shipped when all referencing
# tasks are done; specs 001+002 are shipped; stale-spec-check flags ready-to-archive.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# 1. Script exists and supports --dry-run.
test -x .claude/scripts/spec-status-sync.sh || { echo "FAIL: spec-status-sync.sh missing/not executable"; exit 1; }
bash .claude/scripts/spec-status-sync.sh --dry-run >/dev/null 2>&1 || { echo "FAIL: --dry-run errored"; exit 1; }

# 2. Synthetic: a spec with one task, task done → sync flips to shipped.
tmp=$(mktemp -d)
mkdir -p "$tmp/specs/active" "$tmp/tasks"
printf -- '---\nid: 999\nslug: synth\nstatus: approved\n---\n# synth\n' > "$tmp/specs/active/999-synth.md"
printf -- '- [x] T-999 | spec:999 | phase:1 | done\n' > "$tmp/tasks/TASKS.md"
SPECS_DIR="$tmp/specs/active" TASKS_FILE="$tmp/tasks/TASKS.md" TODAY=2026-05-29 \
  bash .claude/scripts/spec-status-sync.sh >/dev/null 2>&1
grep -q '^status: shipped' "$tmp/specs/active/999-synth.md" || { echo "FAIL: synth spec not advanced to shipped"; rm -rf "$tmp"; exit 1; }

# 3. Synthetic negative: an open task keeps status approved.
printf -- '---\nid: 998\nslug: synb\nstatus: approved\n---\n' > "$tmp/specs/active/998-synb.md"
printf -- '- [ ] T-998 | spec:998 | open\n' >> "$tmp/tasks/TASKS.md"
SPECS_DIR="$tmp/specs/active" TASKS_FILE="$tmp/tasks/TASKS.md" TODAY=2026-05-29 \
  bash .claude/scripts/spec-status-sync.sh >/dev/null 2>&1
grep -q '^status: approved' "$tmp/specs/active/998-synb.md" || { echo "FAIL: open-task spec wrongly advanced"; rm -rf "$tmp"; exit 1; }
rm -rf "$tmp"

# 4. Real specs 001 + 002 are shipped (their tasks are all done).
for s in 001-harness-hardening 002-audit-remediation; do
  grep -q '^status: shipped' "specs/active/$s.md" || { echo "FAIL: $s not shipped"; exit 1; }
done

# 5. stale-spec-check flags 100%-complete approved specs.
grep -qE 'ready.to.archive|100%|all tasks' .github/workflows/stale-spec-check.yml || { echo "FAIL: stale-spec-check not tightened"; exit 1; }

echo "PASS: AC-15/16/17 spec-status-sync + ship 001/002 + stale-spec tightening"
exit 0
