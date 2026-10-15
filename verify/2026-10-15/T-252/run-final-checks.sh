#!/usr/bin/env bash
set -u
out=verify/2026-10-15/T-252
printf '0\tbash .claude/scripts/test/factory-intake-slack.sh phase2 (ledger green.log)\n' > "$out/manifest.tsv"
python3 - "$out/green.log" > "$out/inventory.log" 2>&1 <<'PY'
from pathlib import Path
import sys
text=Path(sys.argv[1]).read_text()
actual=[line for line in text.splitlines() if line.startswith(('phase2 selector: ','phase2 regression: ','phase2 complete: '))]
expected=['phase2 selector: '+name for name in ['hosted-journey','authenticated','edits-replay','publication','checkpoint','checkpoint-failure']]+['phase2 regression: '+name for name in ['factory-legacy-feedback','factory-slack-feedback','factory-encrypted-feedback','factory-hosted-feedback']]+['phase2 complete: 6 intake selectors, 4 feedback regressions']
assert actual==expected,(actual,expected)
assert 'exit_code: 0' in text
print('Exact ordered inventory verified: all six selectors and all four regressions completed once with exit 0.')
PY
printf '%s\t%s\n' "$?" 'phase2 green.log exact ordered inventory assertions' >> "$out/manifest.tsv"
bash .claude/scripts/test/factory-intake-slack.sh > "$out/default-authenticated.log" 2>&1
printf '%s\t%s\n' "$?" 'bash .claude/scripts/test/factory-intake-slack.sh (unchanged default)' >> "$out/manifest.tsv"
bash -n .claude/scripts/test/factory-intake-slack.sh > "$out/bash-syntax.log" 2>&1
printf '%s\t%s\n' "$?" 'bash -n .claude/scripts/test/factory-intake-slack.sh' >> "$out/manifest.tsv"
git diff --check > "$out/diff-check.log" 2>&1
printf '%s\t%s\n' "$?" 'git diff --check' >> "$out/manifest.tsv"
bash .claude/scripts/validate.sh > "$out/validate.log" 2>&1
printf '%s\t%s\n' "$?" 'bash .claude/scripts/validate.sh' >> "$out/manifest.tsv"
shasum -a 256 .claude/scripts/test/factory-intake-slack.sh docs/FACTORY-REQUEST-INTAKE.md > "$out/source-sha256.txt"
cat "$out/manifest.tsv"
